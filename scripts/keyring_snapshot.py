#!/usr/bin/env python3
"""Export and restore Secret Service items without printing secret values."""

from __future__ import annotations

import argparse
import base64
import json
import logging
import os
from pathlib import Path

import gi

from logging_utils import get_logger, log_call

gi.require_version("Secret", "1")
from gi.repository import Gio, GLib, Secret  # noqa: E402

LOGGER = get_logger("keyring-snapshot", "python-helpers.log")


def load_service() -> Secret.Service:
    """Return Secret Service with every available collection unlocked and loaded.

    This helper never requests an interactive unlock. The installer first
    restarts the daemon with an empty password on stdin, which silently unlocks
    automatic-login keyrings. A genuinely password-protected collection must be
    unlocked by the user before the migration is run again so its items are not
    discarded.
    """
    service = Secret.Service.get_sync(Secret.ServiceFlags.LOAD_COLLECTIONS, None)
    for collection in service.get_collections():
        if collection.get_locked():
            LOGGER.warning("Keyring collection %r is locked", collection.get_label())
            raise RuntimeError(
                f"Keyring collection {collection.get_label()!r} is locked; "
                "unlock it once before running the migration"
            )
        collection.load_items_sync(None)
    return service


@log_call(LOGGER, logging.INFO)
def export_items(path: Path) -> int:
    """Write all user items to a mode-0600 JSON snapshot."""
    items: list[dict[str, object]] = []
    for collection in load_service().get_collections():
        if collection.get_object_path().endswith("/session"):
            continue
        for item in collection.get_items() or []:
            attributes = dict(item.get_attributes())
            # This legacy helper unlocks another encrypted keyring. Restoring it
            # would reintroduce the prompt that this migration removes.
            if "keyring" in attributes:
                LOGGER.info("Skipping legacy keyring-unlock helper item")
                continue
            item.load_secret_sync(None)
            value = item.get_secret()
            if value is None:
                raise RuntimeError(f"Could not read keyring item {item.get_label()!r}")
            raw_secret = value.get()
            items.append(
                {
                    "attributes": attributes,
                    "content_type": value.get_content_type(),
                    "label": item.get_label(),
                    "secret": base64.b64encode(raw_secret).decode("ascii"),
                }
            )

    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(items, handle, separators=(",", ":"), sort_keys=True)
    os.chmod(path, 0o600)
    LOGGER.info("Exported %d keyring item(s) to %s", len(items), path)
    print(f"Exported {len(items)} keyring item(s)")
    return len(items)


@log_call(LOGGER)
def login_collection(service: Secret.Service) -> Secret.Collection:
    """Find the passwordless Login collection created by PAM initialization."""
    for collection in service.get_collections():
        if collection.get_object_path().endswith("/login"):
            if collection.get_locked():
                raise RuntimeError("The replacement Login keyring is locked")
            return collection
    raise RuntimeError("The replacement Login keyring was not created")


def create_raw_item(
    collection: Secret.Collection,
    attributes: dict[str, str],
    label: str,
    raw_secret: bytes,
    content_type: str,
) -> None:
    """Create an item through D-Bus so arbitrary binary secrets are retained."""
    LOGGER.info("Creating keyring item %r with content type %s", label, content_type)
    service_proxy = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION,
        Gio.DBusProxyFlags.NONE,
        None,
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets",
        "org.freedesktop.Secret.Service",
        None,
    )
    session = service_proxy.call_sync(
        "OpenSession",
        GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    ).unpack()[1]
    collection_proxy = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION,
        Gio.DBusProxyFlags.NONE,
        None,
        "org.freedesktop.secrets",
        collection.get_object_path(),
        "org.freedesktop.Secret.Collection",
        None,
    )
    properties = {
        "org.freedesktop.Secret.Item.Attributes": GLib.Variant("a{ss}", attributes),
        "org.freedesktop.Secret.Item.Label": GLib.Variant("s", label),
    }
    parameters = GLib.Variant(
        "(a{sv}(oayays)b)",
        (properties, (session, b"", raw_secret, content_type), False),
    )
    _item_path, prompt_path = collection_proxy.call_sync(
        "CreateItem", parameters, Gio.DBusCallFlags.NONE, -1, None
    ).unpack()
    if prompt_path != "/":
        raise RuntimeError(f"Secret Service requested an unexpected prompt for {label!r}")


@log_call(LOGGER, logging.INFO)
def import_items(path: Path) -> int:
    """Restore snapshot items into Login and make it the default collection."""
    with path.open(encoding="utf-8") as handle:
        items = json.load(handle)

    service = load_service()
    collection = login_collection(service)
    service.set_alias_sync("default", collection, None)

    for item in items:
        raw_secret = base64.b64decode(item["secret"], validate=True)
        create_raw_item(
            collection,
            item["attributes"],
            item["label"],
            raw_secret,
            item["content_type"],
        )
    LOGGER.info("Restored %d keyring item(s) from %s", len(items), path)
    print(f"Restored {len(items)} keyring item(s)")
    return len(items)


@log_call(LOGGER, logging.INFO)
def check_keyring() -> None:
    """Require an unlocked Login collection and verify the default alias."""
    service = load_service()
    collection = login_collection(service)
    default = Secret.Collection.for_alias_sync(service, "default", 0, None)
    if default is None or default.get_object_path() != collection.get_object_path():
        LOGGER.error("Login collection is not the default keyring collection")
        raise RuntimeError("Login is not the default keyring collection")
    LOGGER.info("Prompt-free Login keyring is unlocked and default")
    print("Prompt-free Login keyring is unlocked")


def store_test_item(attribute: str, value: str, password: str) -> None:
    """Create one fixture item for the isolated integration test."""
    LOGGER.info("Storing isolated keyring migration test items")
    service = load_service()
    collection = login_collection(service)
    service.set_alias_sync("default", collection, None)
    attributes = {attribute: value, "xdg:schema": "keyring.migration.test"}
    create_raw_item(
        collection,
        attributes,
        "Migration test",
        password.encode(),
        "text/plain",
    )
    create_raw_item(
        collection,
        {"xdg:schema": "keyring.migration.binary-test"},
        "Binary migration test",
        bytes([0x94, 0x00, 0xFF]),
        "application/octet-stream",
    )


def verify_test_item(attribute: str, value: str, password: str) -> None:
    """Verify the isolated integration-test fixture after restoration."""
    LOGGER.info("Verifying isolated keyring migration test items")
    service = load_service()
    collection = login_collection(service)
    collection.load_items_sync(None)
    restored: dict[str, bytes] = {}
    for item in collection.get_items() or []:
        item.load_secret_sync(None)
        secret = item.get_secret()
        if secret is not None:
            restored[item.get_attributes().get("xdg:schema", "")] = secret.get()
    if restored.get("keyring.migration.test") != password.encode():
        LOGGER.error("Migrated text item did not retain its secret")
        raise RuntimeError("Migrated text item did not retain its secret")
    if restored.get("keyring.migration.binary-test") != bytes([0x94, 0x00, 0xFF]):
        LOGGER.error("Migrated binary item did not retain its secret")
        raise RuntimeError("Migrated binary item did not retain its secret")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check")
    for command in ("export", "import"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("path", type=Path)
    for command in ("store-test-item", "verify-test-item"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("attribute")
        subparser.add_argument("value")
        subparser.add_argument("password")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    LOGGER.info("Running keyring snapshot command: %s", args.command)
    if args.command == "export":
        export_items(args.path)
    elif args.command == "import":
        import_items(args.path)
    elif args.command == "check":
        check_keyring()
    elif args.command == "store-test-item":
        store_test_item(args.attribute, args.value, args.password)
    else:
        verify_test_item(args.attribute, args.value, args.password)


if __name__ == "__main__":
    main()
