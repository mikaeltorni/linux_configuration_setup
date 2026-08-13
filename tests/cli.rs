//! CLI contract for lcs-tools gsettings and metadata helpers.

use std::path::PathBuf;
use std::process::Command;
use tempfile::tempdir;

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_lcs-tools"))
}

#[test]
fn append_remove_and_contains_round_trip() {
    let added = bin()
        .args(["append", "dash-to-panel@x"])
        .env("CURRENT", "['a']")
        .output()
        .expect("append");
    assert!(added.status.success());
    let added_out = String::from_utf8_lossy(&added.stdout);
    assert!(added_out.contains("dash-to-panel@x"));
    assert!(added_out.contains("'a'"));

    let hit = bin()
        .args(["contains", "a"])
        .env("CURRENT", "['a']")
        .status()
        .expect("contains hit");
    assert!(hit.success());
    let miss = bin()
        .args(["contains", "z"])
        .env("CURRENT", "['a']")
        .status()
        .expect("contains miss");
    assert_eq!(miss.code(), Some(1));

    let removed = bin()
        .args(["remove", "dash-to-panel@x"])
        .env("CURRENT", "['a', 'dash-to-panel@x']")
        .output()
        .expect("remove");
    assert!(removed.status.success());
    assert_eq!(String::from_utf8_lossy(&removed.stdout).trim(), "['a']");
}

#[test]
fn patch_metadata_appends_and_pins() {
    let dir = tempdir().expect("tempdir");
    let path = dir.path().join("metadata.json");
    std::fs::write(
        &path,
        r#"{"uuid":"x@ext","shell-version":["45"],"version":27}"#,
    )
    .expect("write");
    let out = bin()
        .args(["patch-metadata", path.to_str().unwrap(), "46", "9999"])
        .output()
        .expect("patch");
    assert!(
        out.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = std::fs::read_to_string(&path).expect("read");
    assert!(text.contains("\"46\""), "{text}");
    assert!(text.contains("9999"), "{text}");
}

#[test]
fn rejects_wrong_usage() {
    let none = bin().output().expect("no args");
    assert_eq!(none.status.code(), Some(2));
}

#[test]
fn extract_cursor_writes_png_and_hotspot() {
    let dir = tempdir().expect("tempdir");
    let out = dir.path().join("purple-cross.png");
    let asset = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("configs/cursors/purple_cross.cur");
    let result = bin()
        .args([
            "extract-cursor",
            asset.to_str().unwrap(),
            out.to_str().unwrap(),
            "32",
        ])
        .output()
        .expect("extract-cursor");
    assert!(
        result.status.success(),
        "stderr={}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&result.stdout).trim(), "9 9");
    assert!(out.is_file());
}
