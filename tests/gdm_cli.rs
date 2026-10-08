//! Public checks for the gdm-x11 binary.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::Command;

const OBSERVED: &str = "# GDM configuration storage\n[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=mk\n#WaylandEnable=false\n[security]\nDisallowTCP=true\n";

const OBSERVED_AFTER: &str = "# GDM configuration storage\n[daemon]\nWaylandEnable=false\nXorgEnable=true\nPreferredDisplayServer=xorg\nAutomaticLoginEnable=true\nAutomaticLogin=mk\n#WaylandEnable=false\n[security]\nDisallowTCP=true\n";

const SHAPE1_AFTER: &str = "# comment\n[security]\nWaylandEnable=true\n\n[daemon]\nWaylandEnable=false\nXorgEnable=true\nPreferredDisplayServer=xorg\n";

const SHAPE2_AFTER: &str = "[daemon]\nWaylandEnable=false\nXorgEnable=true\nPreferredDisplayServer=xorg\n[security]\nWaylandEnable=true\n";

fn root(label: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!(
        "gdm-x11-{}-{}-{}",
        label,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir_all(&path).unwrap();
    path
}

fn run(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_gdm-x11"))
        .args(args)
        .output()
        .expect("gdm-x11 runs")
}

#[test]
fn apply_matches_python_and_a_second_run_keeps_the_file() {
    let dir = root("observed");
    let sessions = dir.join("sessions");
    fs::create_dir_all(&sessions).unwrap();
    fs::write(sessions.join("ubuntu-xorg.desktop"), "[Desktop Entry]\n").unwrap();
    let conf = dir.join("custom.conf");
    fs::write(&conf, OBSERVED).unwrap();
    fs::set_permissions(&conf, fs::Permissions::from_mode(0o640)).unwrap();
    let first = run(&["apply", conf.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(first.status.code(), Some(0), "{:?}", first);
    assert!(first.stderr.is_empty(), "{:?}", String::from_utf8_lossy(&first.stderr));
    let stdout = String::from_utf8(first.stdout).unwrap();
    assert_eq!(
        stdout,
        "GDM will use X11 on the next login. Log out and back in when ready; the running session is unchanged.\n"
    );
    assert_eq!(fs::read_to_string(&conf).unwrap(), OBSERVED_AFTER);
    assert_eq!(fs::metadata(&conf).unwrap().permissions().mode() & 0o777, 0o640);
    let backup = dir.join("custom.conf.before-x11-session");
    assert_eq!(fs::read_to_string(&backup).unwrap(), OBSERVED);
    let second = run(&["apply", conf.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(second.status.code(), Some(0), "{:?}", second);
    assert_eq!(fs::read_to_string(&conf).unwrap(), OBSERVED_AFTER);
    assert_eq!(fs::read_to_string(&backup).unwrap(), OBSERVED);
    let check = run(&["check", conf.to_str().unwrap()]);
    assert_eq!(check.status.code(), Some(0), "{:?}", check);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn shapes_keep_other_sections() {
    let dir = root("shapes");
    let sessions = dir.join("sessions");
    fs::create_dir_all(&sessions).unwrap();
    fs::write(sessions.join("ubuntu.desktop"), "name\n").unwrap();
    let first = dir.join("shape1.conf");
    fs::write(&first, "# comment\n[security]\nWaylandEnable=true\n").unwrap();
    let result = run(&["apply", first.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(result.status.code(), Some(0), "{:?}", result);
    assert_eq!(fs::read_to_string(&first).unwrap(), SHAPE1_AFTER);
    let second = dir.join("shape2.conf");
    fs::write(
        &second,
        "[daemon]\n WaylandEnable = true\nWaylandEnable=true\nXorgEnable=false\nPreferredDisplayServer=wayland\n[security]\nWaylandEnable=true\n",
    )
    .unwrap();
    let result = run(&["apply", second.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(result.status.code(), Some(0), "{:?}", result);
    assert_eq!(fs::read_to_string(&second).unwrap(), SHAPE2_AFTER);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn rejects_missing_session_malformed_text_and_bad_arguments() {
    let dir = root("reject");
    let sessions = dir.join("sessions");
    fs::create_dir_all(&sessions).unwrap();
    let conf = dir.join("custom.conf");
    fs::write(&conf, OBSERVED).unwrap();
    let missing = run(&["apply", conf.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(missing.status.code(), Some(1), "{:?}", missing);
    assert_eq!(fs::read_to_string(&conf).unwrap(), OBSERVED);
    let stderr = String::from_utf8(missing.stderr).unwrap();
    assert!(stderr.contains("No X11 session in "), "{stderr}");
    fs::write(sessions.join("ubuntu-xorg.desktop"), "ok\n").unwrap();
    fs::write(&conf, "not an INI config\n").unwrap();
    let bad = run(&["apply", conf.to_str().unwrap(), sessions.to_str().unwrap()]);
    assert_eq!(bad.status.code(), Some(1), "{:?}", bad);
    assert_eq!(fs::read_to_string(&conf).unwrap(), "not an INI config\n");
    assert!(!dir.join("custom.conf.before-x11-session").exists());
    let usage = run(&[]);
    assert_eq!(usage.status.code(), Some(2), "{:?}", usage);
    let text = String::from_utf8(usage.stderr).unwrap();
    assert!(text.contains("apply"), "{text}");
    assert!(text.contains("check"), "{text}");
    let before = run(&["check", conf.to_str().unwrap()]);
    assert_eq!(before.status.code(), Some(1), "{:?}", before);
    let _ = fs::remove_dir_all(dir);
}
