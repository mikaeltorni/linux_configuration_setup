//! Public, isolated Secret Service checks; never connect to the desktop bus.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Output};

/// Start a separate bus/daemon in an isolated home and run public commands.
/// Parameters: home - isolated home; password - PAM fixture password; script - shell assertions; args - extra paths.
/// Returns: complete sandbox process output/status.
fn session(home: &Path, password: &str, script: &str, args: &[&Path]) -> Output {
    fs::create_dir_all(home.join("runtime")).unwrap();
    fs::set_permissions(home.join("runtime"), fs::Permissions::from_mode(0o700)).unwrap();
    Command::new("timeout")
        .args([
            "40",
            "dbus-run-session",
            "--",
            "bash",
            "-euo",
            "pipefail",
            "-c",
        ])
        .arg(
            r#"printf '%s\n' "$1" | gnome-keyring-daemon --login >/dev/null
eval "$(gnome-keyring-daemon --start --components=secrets)"
bash -euo pipefail -c "$2" bash "$3" "${@:4}""#,
        )
        .arg("bash")
        .arg(password)
        .arg(script)
        .arg(env!("CARGO_BIN_EXE_keyring-snapshot"))
        .args(args)
        .env("HOME", home)
        .env("XDG_CONFIG_HOME", home.join(".config"))
        .env("XDG_DATA_HOME", home.join(".local/share"))
        .env("XDG_RUNTIME_DIR", home.join("runtime"))
        .env("GNOME_KEYRING_CONTROL", home.join("runtime/keyring"))
        .output()
        .unwrap()
}

/// Require a sandbox to succeed without printing any supplied fixture secret.
/// Parameters: output - sandbox result.
/// Returns: None.
fn successful(output: Output) {
    assert_eq!(
        output.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    for stream in [&output.stdout, &output.stderr] {
        assert!(!String::from_utf8_lossy(stream).contains("test-secret"));
    }
}

#[test]
/// Preserve text/binary attributes, content types and secrets across fresh empty-password sessions.
/// Parameters: none.
/// Returns: None.
fn migration_round_trip_and_repeated_checks_match_original_messages() {
    let root = tempfile::tempdir().unwrap();
    let snapshot = root.path().join("items.json");
    fs::write(&snapshot, "placeholder").unwrap();
    fs::set_permissions(&snapshot, fs::Permissions::from_mode(0o644)).unwrap();
    successful(session(
        &root.path().join("source"),
        "test-password",
        r#"
"$1" store-test-item account demo test-secret
[[ "$("$1" export "$2")" == 'Exported 2 keyring item(s)' ]]
"#,
        &[&snapshot],
    ));
    assert_eq!(
        fs::metadata(&snapshot).unwrap().permissions().mode() & 0o777,
        0o600
    );
    let document: serde_json::Value =
        serde_json::from_slice(&fs::read(&snapshot).unwrap()).unwrap();
    let rows = document.as_array().unwrap();
    assert_eq!(rows.len(), 2);
    let text = rows
        .iter()
        .find(|row| row["label"] == "Migration test")
        .unwrap();
    assert_eq!(
        text["attributes"],
        serde_json::json!({"account":"demo","xdg:schema":"keyring.migration.test"})
    );
    assert_eq!(text["secret"], "dGVzdC1zZWNyZXQ=");
    let binary = rows
        .iter()
        .find(|row| row["label"] == "Binary migration test")
        .unwrap();
    assert_eq!(binary["secret"], "lAD/");
    // The original helper's binary fixture also reads text/plain back from
    // this daemon; GetSecret determines the snapshot content type.
    assert_eq!(binary["content_type"], "text/plain");
    let destination = root.path().join("destination");
    successful(session(
        &destination,
        "",
        r#"
[[ "$("$1" import "$2")" == 'Restored 2 keyring item(s)' ]]
"$1" verify-test-item account demo test-secret
[[ "$("$1" check)" == 'Prompt-free Login keyring is unlocked' ]]
"#,
        &[&snapshot],
    ));
    assert_eq!(
        fs::read_to_string(destination.join(".local/share/keyrings/default"))
            .unwrap()
            .trim(),
        "login"
    );
    for _ in 0..2 {
        successful(session(
            &destination,
            "",
            r#"
[[ "$("$1" check)" == 'Prompt-free Login keyring is unlocked' ]]
"$1" verify-test-item account demo test-secret
"#,
            &[],
        ));
    }
}

#[test]
/// Reject malformed commands/snapshots with immediate public observations of seeded secrets.
/// Parameters: none.
/// Returns: None.
fn rejected_inputs_leave_populated_collection_and_snapshot_unchanged() {
    let root = tempfile::tempdir().unwrap();
    let snapshot = root.path().join("bad.json");
    fs::write(&snapshot, r#"[{"attributes":{},"content_type":"text/plain","label":"valid","secret":"eA=="},{"attributes":{},"content_type":"text/plain","label":"invalid","secret":"%%%%"}]"#).unwrap();
    let before = fs::read(&snapshot).unwrap();
    successful(session(
        &root.path().join("home"),
        "",
        r#"
"$1" store-test-item account demo test-secret
# Reject one command then immediately observe the retained public secret values.
# Parameters: expected - status; remaining tokens - raw command. Returns: zero after assertions.
reject() {
  local expected="$1"; shift
  set +e; "$bin" "$@" > "$capture_path.out" 2> "$capture_path.err"; status=$?; set -e
  [[ "$status" == "$expected" ]]
  "$bin" verify-test-item account demo test-secret
  [[ "$("$bin" export "$export_path")" == 'Exported 2 keyring item(s)' ]]
}
bin="$1"; export_path="$2.observed"; capture_path="$2.trace"
# Shapes do not read files or touch the service.
for command in '' unknown; do
  if [[ -z "$command" ]]; then reject 2; else reject 2 "$command"; fi
done
reject 2 check extra
reject 2 export
reject 2 export "$2" extra
reject 2 import
reject 2 import "$2" extra
reject 2 store-test-item account demo
reject 2 store-test-item account demo test-secret extra
reject 2 verify-test-item account demo
reject 2 verify-test-item account demo test-secret extra
reject 1 import "$2"
reject 1 import "$2.missing"
# A default-alias failure must leave the populated values unchanged.
gdbus call --session --dest org.freedesktop.secrets --object-path /org/freedesktop/secrets --method org.freedesktop.Secret.Service.SetAlias default /org/freedesktop/secrets/collection/session >/dev/null
reject 1 check
"#,
        &[&snapshot],
    ));
    assert_eq!(fs::read(&snapshot).unwrap(), before);
}

#[test]
/// Reject unreadable JSON or wrong record shapes before mutating existing values.
/// Parameters: none.
/// Returns: None.
fn malformed_snapshot_shapes_preserve_existing_values() {
    let root = tempfile::tempdir().unwrap();
    let snapshot = root.path().join("invalid.json");
    for document in [
        "not-json",
        "{}",
        "[{}]",
        r#"[{"attributes":[],"content_type":"text/plain","label":"bad","secret":"eA=="}]"#,
    ] {
        fs::write(&snapshot, document).unwrap();
        // Each rejection gets a fresh populated collection and immediate reads.
        let home = tempfile::tempdir().unwrap();
        successful(session(
            home.path(),
            "",
            r#"
"$1" store-test-item account demo test-secret
set +e; "$1" import "$2" > "$2.out" 2> "$2.err"; status=$?; set -e
[[ "$status" == 1 ]]
"$1" verify-test-item account demo test-secret
[[ "$("$1" export "$2.observed")" == 'Exported 2 keyring item(s)' ]]
"#,
            &[&snapshot],
        ));
        assert_eq!(fs::read_to_string(&snapshot).unwrap(), document);
    }
}

#[test]
/// Refuse locked keyrings without prompts or truncating an existing snapshot.
/// Parameters: none.
/// Returns: None.
fn locked_collections_do_not_prompt_or_overwrite_snapshot() {
    let root = tempfile::tempdir().unwrap();
    let home = root.path().join("home");
    let snapshot = root.path().join("items.json");
    successful(session(
        &home,
        "encrypted-password",
        r#""$1" store-test-item account demo test-secret"#,
        &[],
    ));
    fs::write(&snapshot, "preserve snapshot").unwrap();
    successful(session(
        &home,
        "",
        r#"
set +e
"$1" export "$2" > "$2.out" 2> "$2.err"; status=$?
set -e
[[ "$status" == 1 ]]
[[ "$(cat "$2")" == 'preserve snapshot' ]]
set +e
"$1" check > "$2.out" 2> "$2.err"; status=$?
set -e
[[ "$status" == 1 ]]
[[ "$(cat "$2")" == 'preserve snapshot' ]]
"#,
        &[&snapshot],
    ));
    assert_eq!(fs::read_to_string(&snapshot).unwrap(), "preserve snapshot");
}

#[test]
/// Skip legacy unlock items and session collections during a secret-safe export.
/// Parameters: none.
/// Returns: None.
fn legacy_unlock_items_are_omitted_from_export() {
    let root = tempfile::tempdir().unwrap();
    let snapshot = root.path().join("legacy.json");
    let output = root.path().join("out.json");
    fs::write(&snapshot, r#"[{"attributes":{"keyring":"legacy"},"content_type":"text/plain","label":"Legacy unlock","secret":"bGVnYWN5"}]"#).unwrap();
    successful(session(
        &root.path().join("home"),
        "",
        r#"
"$1" store-test-item account demo test-secret
[[ "$("$1" import "$2")" == 'Restored 1 keyring item(s)' ]]
[[ "$("$1" export "$3")" == 'Exported 2 keyring item(s)' ]]
"$1" verify-test-item account demo test-secret
"#,
        &[&snapshot, &output],
    ));
    let document: serde_json::Value = serde_json::from_slice(&fs::read(output).unwrap()).unwrap();
    assert_eq!(document.as_array().unwrap().len(), 2);
}
