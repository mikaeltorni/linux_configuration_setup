//! Persist a GDM X11 policy without restarting the session.

use std::fs::{self, File};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};

const POLICY: [(&str, &str); 3] = [
    ("WaylandEnable", "false"),
    ("XorgEnable", "true"),
    ("PreferredDisplayServer", "xorg"),
];

/// Parsed GDM helper command.
pub struct GdmArgs {
    /// `apply` or `check`.
    pub operation: String,
    /// GDM configuration path.
    pub configuration: PathBuf,
    /// X session directory. Present for `apply`.
    pub xsessions: Option<PathBuf>,
}

/// Parse `apply` and `check` arguments.
///
/// `args` excludes the program name. The wrong shape is a usage error.
pub fn parse_gdm_args(args: &[String]) -> Result<GdmArgs, String> {
    let usage = "usage: gdm-x11 {apply,check} ...";
    match args {
        [operation, configuration, xsessions] if operation == "apply" => Ok(GdmArgs {
            operation: operation.clone(),
            configuration: PathBuf::from(configuration),
            xsessions: Some(PathBuf::from(xsessions)),
        }),
        [operation, configuration] if operation == "check" => Ok(GdmArgs {
            operation: operation.clone(),
            configuration: PathBuf::from(configuration),
            xsessions: None,
        }),
        _ => Err(usage.to_string()),
    }
}

/// Apply or check the X11 policy.
///
/// Apply prints the login message. Check only sets the exit status.
pub fn run_gdm(args: &GdmArgs) -> Result<String, String> {
    match args.operation.as_str() {
        "apply" => apply_policy(
            &args.configuration,
            args.xsessions.as_deref().ok_or_else(|| "apply requires an X session directory".to_string())?,
        ),
        "check" => {
            let enabled = check_policy(&args.configuration)?;
            if enabled {
                Ok(String::new())
            } else {
                Err(String::new())
            }
        }
        _ => Err("usage: gdm-x11 {apply,check} ...".to_string()),
    }
}

fn apply_policy(configuration: &Path, xsessions: &Path) -> Result<String, String> {
    if !has_desktop_session(xsessions) {
        return Err(format!(
            "Cannot configure/check GDM X11: No X11 session in {}; install an Xorg desktop session before disabling Wayland",
            xsessions.display()
        ));
    }
    let content = fs::read_to_string(configuration).map_err(|error| {
        format!("Cannot configure/check GDM X11: {error}")
    })?;
    validate_ini(&content)?;
    let updated = render_policy(&content);
    validate_ini(&updated)?;
    if updated != content {
        write_configuration(configuration, &updated)?;
    }
    Ok("GDM will use X11 on the next login. Log out and back in when ready; the running session is unchanged.".to_string())
}

fn check_policy(configuration: &Path) -> Result<bool, String> {
    let content = fs::read_to_string(configuration).map_err(|error| {
        format!("Cannot configure/check GDM X11: {error}")
    })?;
    validate_ini(&content)?;
    let settings = daemon_values(&content);
    let preferred = settings
        .iter()
        .rev()
        .find(|(key, _)| key == "PreferredDisplayServer")
        .map(|(_, value)| value.as_str())
        .unwrap_or("wayland");
    let wayland = boolean_setting(&settings, "WaylandEnable", true);
    let xorg = boolean_setting(&settings, "XorgEnable", true);
    Ok(preferred == "xorg" && !wayland && xorg)
}

fn has_desktop_session(xsessions: &Path) -> bool {
    fs::read_dir(xsessions)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .any(|entry| {
            let path = entry.path();
            path.extension().and_then(|ext| ext.to_str()) == Some("desktop") && path.is_file()
        })
}

fn validate_ini(content: &str) -> Result<(), String> {
    let mut seen_section = false;
    for raw in content.split_inclusive('\n') {
        let line = raw.trim_end_matches(['\n', '\r']);
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
            continue;
        }
        if trimmed.starts_with('[') && trimmed.ends_with(']') && trimmed.len() > 2 {
            seen_section = true;
            continue;
        }
        if !seen_section || (!trimmed.contains('=') && !trimmed.contains(':')) {
            return Err("Cannot configure/check GDM X11: malformed configuration".to_string());
        }
    }
    Ok(())
}

fn render_policy(content: &str) -> String {
    let mut lines = Vec::new();
    let mut in_daemon = false;
    let mut found_daemon = false;
    for raw in content.split_inclusive('\n') {
        let had_newline = raw.ends_with('\n');
        let body = raw.trim_end_matches(['\n', '\r']);
        if let Some(name) = section_name(body) {
            in_daemon = name == "daemon";
            let mut line = body.to_string();
            if had_newline || !line.ends_with('\n') {
                if !had_newline {
                    line.push('\n');
                } else if !raw.ends_with('\n') {
                    line.push('\n');
                } else {
                    line = raw.trim_end_matches('\r').to_string();
                    if !line.ends_with('\n') {
                        line.push('\n');
                    }
                }
            }
            if !line.ends_with('\n') {
                line.push('\n');
            }
            lines.push(line);
            if in_daemon && !found_daemon {
                for (key, value) in POLICY {
                    lines.push(format!("{key}={value}\n"));
                }
                found_daemon = true;
            }
        } else if in_daemon && is_policy_key(body) {
            continue;
        } else {
            lines.push(raw.to_string());
        }
    }
    if !found_daemon {
        if let Some(last) = lines.last_mut() {
            if !last.ends_with('\n') {
                last.push('\n');
            }
        }
        lines.push("\n[daemon]\n".to_string());
        for (key, value) in POLICY {
            lines.push(format!("{key}={value}\n"));
        }
    }
    lines.concat()
}

fn section_name(line: &str) -> Option<&str> {
    let trimmed = line.trim();
    let rest = trimmed.strip_prefix('[')?.strip_suffix(']')?;
    if rest.contains(']') {
        return None;
    }
    Some(rest.trim())
}

fn is_policy_key(line: &str) -> bool {
    let trimmed = line.trim_start();
    for key in ["WaylandEnable", "XorgEnable", "PreferredDisplayServer"] {
        if let Some(rest) = trimmed.strip_prefix(key) {
            let rest = rest.trim_start();
            if rest.starts_with('=') || rest.starts_with(':') {
                return true;
            }
        }
    }
    false
}

fn daemon_values(content: &str) -> Vec<(String, String)> {
    let mut values = Vec::new();
    let mut in_daemon = false;
    for raw in content.split_inclusive('\n') {
        let line = raw.trim_end_matches(['\n', '\r']);
        if let Some(name) = section_name(line) {
            in_daemon = name == "daemon";
            continue;
        }
        if !in_daemon || line.trim().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        if let Some((key, value)) = split_setting(line) {
            values.push((key, value));
        }
    }
    values
}

fn split_setting(line: &str) -> Option<(String, String)> {
    let trimmed = line.trim();
    let divider = trimmed.find(['=', ':'])?;
    let key = trimmed[..divider].trim().to_string();
    let value = trimmed[divider + 1..].trim().to_string();
    if key.is_empty() {
        None
    } else {
        Some((key, value))
    }
}

fn boolean_setting(settings: &[(String, String)], key: &str, fallback: bool) -> bool {
    let Some(value) = settings.iter().rev().find(|(name, _)| name == key).map(|(_, value)| value) else {
        return fallback;
    };
    !matches!(value.to_ascii_lowercase().as_str(), "0" | "false" | "no" | "off")
}

fn write_configuration(configuration: &Path, content: &str) -> Result<(), String> {
    let backup = PathBuf::from(format!("{}.before-x11-session", configuration.display()));
    if !backup.exists() {
        fs::copy(configuration, &backup).map_err(|error| error.to_string())?;
    }
    let metadata = fs::metadata(configuration).map_err(|error| error.to_string())?;
    let parent = configuration.parent().unwrap_or_else(|| Path::new("."));
    let temporary_name = parent.join(format!(".x11-session-{}", std::process::id()));
    let mut temporary = File::create(&temporary_name).map_err(|error| error.to_string())?;
    temporary.write_all(content.as_bytes()).map_err(|error| error.to_string())?;
    if metadata.uid() == fs::metadata("/proc/self").map(|meta| meta.uid()).unwrap_or(u32::MAX) {
        let _ = std::os::unix::fs::chown(&temporary_name, Some(metadata.uid()), Some(metadata.gid()));
    }
    let mut permissions = metadata.permissions();
    permissions.set_mode(metadata.mode() & 0o7777);
    fs::set_permissions(&temporary_name, permissions).map_err(|error| error.to_string())?;
    fs::rename(&temporary_name, configuration).map_err(|error| {
        let _ = fs::remove_file(&temporary_name);
        error.to_string()
    })?;
    Ok(())
}
