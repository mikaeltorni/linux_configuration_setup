# Native keyring public checks

Capability queue: authoritative [workflow ledger](/home/mk/projects/installation_scripts/tmp/workflow/6500c77863834cf58c7ec79332b5335a.md), row 1. Current checkpoint is native-keyring-snapshot (steps 27–29): export/import/check and retained fixture commands. All later desktop inline and shared configurator ports remain deferred.

Runner: `cargo test --offline --locked --release --test keyring_cli`.
Every bus, daemon, home and mutable collection is isolated; no desktop service
or real credential is accessed.

| Contract | Saved public assertion |
| --- | --- |
| Export/import/check stdout and bytes | `migration_round_trip_and_repeated_checks_match_original_messages`: exact messages, base64 text/binary, attributes/content type, mode 0600; empty-password reopened sessions twice; Login default file. |
| Empty/unknown/missing/extra tokens for each command | `rejected_inputs_leave_populated_collection_and_snapshot_unchanged`: status two immediately followed by public fixture verification and export count two. |
| Invalid base64 late in snapshot, missing file | Same test: status one before import side effects; public verification/count immediately; input bytes preserved. |
| Invalid JSON and record shapes | `malformed_snapshot_shapes_preserve_existing_values`: fresh populated state per input, status one, immediate public verification/export and unchanged input bytes. |
| Default alias points elsewhere | Populated rejection test selects session through fixture D-Bus setup, rejects check with status one and immediately verifies/exports retained values. GNOME falls back to Login when the alias is simply removed. |
| Locked resources | `locked_collections_do_not_prompt_or_overwrite_snapshot`: fresh locked daemon, no unlock invocation, bounded timeout; snapshot preserved immediately after each rejection. |
| Legacy helper exclusion | `legacy_unlock_items_are_omitted_from_export`: seeded legacy item omitted, independent text/binary retained. |

All operands are text/paths, not numbers. Fixture commands retain their existing
arity. No new public collection creation/unlock/reset command is introduced.
Runtime output never includes fixture passwords or serialized secret bytes.

Original daemon observation: the Python fixture creates application/octet-stream,
but its GetSecret response reports text/plain. The snapshot assertion follows
that independently captured response; binary bytes remain `94 00 ff`.
