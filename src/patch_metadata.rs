//! Patch GNOME extension `metadata.json` shell-version and version pin.

use std::fs;
use std::path::Path;

use serde_json::{json, Value};

use crate::logging;

/// Add `shell_version` to the `shell-version` list when missing.
///
/// # Parameters
/// - `data`: Parsed metadata object (mutated in place).
/// - `shell_version`: Version string to ensure (e.g. `"46"`).
///
/// # Returns
/// `true` when the object changed.
pub fn patch_shell_version(data: &mut Value, shell_version: &str) -> bool {
    match data.get_mut("shell-version") {
        Some(Value::Array(sv)) => {
            if sv.iter().any(|v| v.as_str() == Some(shell_version)) {
                false
            } else {
                sv.push(Value::String(shell_version.to_string()));
                true
            }
        }
        _ => {
            data["shell-version"] = json!([shell_version]);
            true
        }
    }
}

/// Raise the integer `version` field to at least `min_version`.
///
/// # Parameters
/// - `data`: Parsed metadata object (mutated in place).
/// - `min_version`: Minimum version to pin (e.g. `9999`).
///
/// # Returns
/// `true` when the object changed.
pub fn pin_version(data: &mut Value, min_version: i64) -> bool {
    let current = match data.get("version") {
        Some(Value::Number(n)) => n.as_i64().unwrap_or(0),
        Some(Value::String(s)) => s.parse::<i64>().unwrap_or(0),
        _ => 0,
    };
    if current >= min_version {
        return false;
    }
    data["version"] = json!(min_version);
    true
}

fn write_json(path: &Path, data: &Value) -> Result<(), String> {
    let text = serde_json::to_string(data).map_err(|e| e.to_string())?;
    fs::write(path, text).map_err(|e| e.to_string())
}

/// CLI: `patch-metadata <metadata.json> <shell-version> [pin-version]`.
///
/// # Returns
/// `0` on success. `1` on usage, missing file, or invalid JSON.
pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 || args.len() > 4 || args[0] != "patch-metadata" {
        logging::error(
            "Usage: lcs-tools patch-metadata <metadata.json> <shell-version> [pin-version]",
        );
        eprintln!("Usage: lcs-tools patch-metadata <metadata.json> <shell-version> [pin-version]");
        return 1;
    }
    let path = Path::new(&args[1]);
    let shell_version = &args[2];
    let pin = args.get(3).and_then(|s| s.parse::<i64>().ok());
    if !path.is_file() {
        logging::error(format!("Metadata file not found: {}", path.display()));
        eprintln!("Error: Metadata file not found: {}", path.display());
        return 1;
    }
    let raw = match fs::read_to_string(path) {
        Ok(s) => s,
        Err(err) => {
            logging::error(format!("Could not read {}: {err}", path.display()));
            eprintln!("Error: {err}");
            return 1;
        }
    };
    let mut data: Value = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(err) => {
            logging::error(format!("Invalid JSON in {}: {err}", path.display()));
            eprintln!("Error: Invalid JSON in {}: {err}", path.display());
            return 1;
        }
    };
    if !data.is_object() {
        logging::error(format!(
            "Metadata root is not an object: {}",
            path.display()
        ));
        eprintln!(
            "Error: Invalid JSON in {}: root is not an object",
            path.display()
        );
        return 1;
    }

    let mut dirty = false;
    if patch_shell_version(&mut data, shell_version) {
        dirty = true;
        logging::info(format!(
            "Patched shell-version in {} to include {shell_version}",
            path.display()
        ));
        println!("Patched shell-version in metadata.json to include {shell_version}");
    } else {
        logging::info(format!(
            "Shell version {shell_version} already present in {}",
            path.display()
        ));
        println!("Shell version '{shell_version}' already present — no changes made.");
    }

    if let Some(min_version) = pin {
        if pin_version(&mut data, min_version) {
            dirty = true;
            logging::info(format!(
                "Pinned {} version to {min_version}",
                path.display()
            ));
            println!("Pinned metadata.json version to {min_version}");
        } else {
            logging::info(format!(
                "Version already pinned at or above {min_version} in {}",
                path.display()
            ));
            println!("Version already pinned at or above {min_version} — no changes made.");
        }
    }

    if dirty {
        if let Err(err) = write_json(path, &data) {
            logging::error(format!("Could not write {}: {err}", path.display()));
            eprintln!("Error: {err}");
            return 1;
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn appends_missing_shell_version() {
        let mut data = json!({"uuid": "x@ext", "shell-version": ["45"]});
        assert!(patch_shell_version(&mut data, "46"));
        assert_eq!(data["shell-version"], json!(["45", "46"]));
        assert!(!patch_shell_version(&mut data, "46"));
    }

    #[test]
    fn replaces_non_list_shell_version() {
        let mut data = json!({"uuid": "x@ext", "shell-version": "broken"});
        assert!(patch_shell_version(&mut data, "46"));
        assert_eq!(data["shell-version"], json!(["46"]));
    }

    #[test]
    fn pins_version_when_lower() {
        let mut data = json!({"uuid": "x@ext", "version": 27});
        assert!(pin_version(&mut data, 9999));
        assert_eq!(data["version"], json!(9999));
        assert!(!pin_version(&mut data, 9999));
    }
}
