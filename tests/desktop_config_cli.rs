//! Public checks for desktop installer file operations.

use std::fs;
use std::process::{Command, Output};

/// Run the complete public native process interface.
/// Parameters: args - raw tokens excluding executable name.
/// Returns: captured exit/output.
fn run(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_desktop-config"))
        .args(args)
        .output()
        .unwrap()
}

/// Build the exact original filter arguments with independent fixture text.
/// Parameters: path - config path; state - selected mode.
/// Returns: complete raw argv for one filter call.
fn filter<'a>(path: &'a str, state: &'a str) -> Vec<&'a str> {
    vec![
        "kitty-filter",
        path,
        state,
        "# managed current",
        "# legacy",
        "map conditional apostrophe discard_event",
        "map apostrophe ",
        "map conditional apostrophe ",
    ]
}

#[test]
/// Reconcile managed mappings and preserve unrelated text through repeated on/off calls.
/// Parameters: none.
/// Returns: None.
fn kitty_filter_round_trip_preserves_user_text() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("世界 config/kitty.conf");
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(&path, "# user\r\nfont_size 13\r\n\r\n# legacy\r\nmap apostrophe no_op\r\nmap shift+apostrophe send_text all x\r\n").unwrap();
    for _ in 0..2 {
        let result = run(&filter(path.to_str().unwrap(), "on"));
        assert_eq!(result.status.code(), Some(0), "{:?}", result);
        assert!(result.stdout.is_empty());
        assert_eq!(fs::read_to_string(&path).unwrap(), "# user\nfont_size 13\nmap shift+apostrophe send_text all x\n\n# managed current\nmap conditional apostrophe discard_event\n");
    }
    for _ in 0..2 {
        let result = run(&filter(path.to_str().unwrap(), "off"));
        assert_eq!(result.status.code(), Some(0));
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "# user\nfont_size 13\nmap shift+apostrophe send_text all x\n"
        );
    }
    let missing = root.path().join("new/kitty.conf");
    assert_eq!(
        run(&filter(missing.to_str().unwrap(), "on")).status.code(),
        Some(0)
    );
    assert_eq!(fs::read_to_string(missing).unwrap(), "# Managed by linux_configuration_setup.\n\n# managed current\nmap conditional apostrophe discard_event\n");
}

#[test]
/// Remove only original default prefixes and their preceding comment/blank blocks.
/// Parameters: none.
/// Returns: None.
fn kitty_default_removal_preserves_unrelated_settings() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("kitty.conf");
    fs::write(&path, "# user\nfont_size 13\n\n# managed\nconfirm_os_window_close 0\n\n# managed\nmap ctrl+backspace send_key ctrl+w\nbackground_opacity 0.9\n# managed\nwayland_titlebar_color background\n\n").unwrap();
    for _ in 0..2 {
        let result = run(&["kitty-defaults-remove", path.to_str().unwrap()]);
        assert_eq!(result.status.code(), Some(0));
        assert!(result.stdout.is_empty());
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "# user\nfont_size 13\nbackground_opacity 0.9\n"
        );
    }
}

#[test]
/// Replace the unit root literally, preserving unrelated directives and repeated output.
/// Parameters: none.
/// Returns: None.
fn unit_render_handles_spaces_unicode_and_literal_shell_characters() {
    let root = tempfile::tempdir().unwrap();
    let source = root.path().join("source.service");
    let dest = root.path().join("dest.service");
    fs::write(&source, "[Service]\r\nEnvironment=LCS_SCRIPT_DIR=@LCS_SCRIPT_DIR@\r\nOther=@OTHER@\r\nExecStart=@LCS_SCRIPT_DIR@/run\r\n").unwrap();
    let checkout = "/世界 project/$literal`text`";
    for _ in 0..2 {
        let result = run(&[
            "render-unit",
            source.to_str().unwrap(),
            dest.to_str().unwrap(),
            checkout,
        ]);
        assert_eq!(result.status.code(), Some(0));
        assert!(result.stdout.is_empty());
        assert_eq!(fs::read_to_string(&dest).unwrap(), "[Service]\nEnvironment=LCS_SCRIPT_DIR=/世界 project/$literal`text`\nOther=@OTHER@\nExecStart=/世界 project/$literal`text`/run\n");
    }
}

#[test]
/// Reject malformed dispatch, modes and missing resources without changing populated files.
/// Parameters: none.
/// Returns: None.
fn rejections_preserve_existing_config_and_unit() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("kitty.conf");
    fs::write(&path, "font_size 13\n").unwrap();
    let name = path.to_str().unwrap();
    let mut missing_filter = filter(name, "on");
    missing_filter.pop();
    let mut extra_filter = filter(name, "on");
    extra_filter.push("extra");
    for args in [
        vec![],
        vec!["unknown"],
        missing_filter,
        extra_filter,
        vec!["kitty-defaults-remove"],
        vec!["kitty-defaults-remove", name, "extra"],
        vec!["render-unit", name, name],
        vec!["render-unit", name, name, "root", "extra"],
    ] {
        assert_eq!(run(&args).status.code(), Some(2));
        assert_eq!(fs::read_to_string(&path).unwrap(), "font_size 13\n");
    }
    assert_eq!(run(&filter(name, "maybe")).status.code(), Some(2));
    assert_eq!(fs::read_to_string(&path).unwrap(), "font_size 13\n");
    let missing = root.path().join("missing");
    assert_eq!(
        run(&["render-unit", missing.to_str().unwrap(), name, "root"])
            .status
            .code(),
        Some(1)
    );
    assert_eq!(fs::read_to_string(&path).unwrap(), "font_size 13\n");
    assert_eq!(
        run(&["kitty-defaults-remove", missing.to_str().unwrap()])
            .status
            .code(),
        Some(1)
    );
    assert_eq!(fs::read_to_string(&path).unwrap(), "font_size 13\n");
}
