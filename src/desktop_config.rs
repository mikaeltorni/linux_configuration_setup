//! Native owners for literal desktop installer file edits.

use std::fs;
use std::path::{Path, PathBuf};

const USAGE: &str = "usage: desktop-config render-unit SOURCE DEST ROOT | kitty-defaults-remove PATH | kitty-filter PATH on|off COMMENT LEGACY_COMMENT MAPPING LEGACY_PREFIX MAPPING_PREFIX";

pub struct FilterText {
    comment: String,
    legacy_comment: String,
    mapping: String,
    legacy_prefix: String,
    mapping_prefix: String,
}

pub enum Command {
    Help,
    Render {
        source: PathBuf,
        dest: PathBuf,
        root: String,
    },
    DefaultsRemove(PathBuf),
    Filter {
        path: PathBuf,
        enabled: bool,
        text: FilterText,
    },
}

/// Parse all raw command shapes into complete operation arguments.
/// Parameters: args - raw argv excluding the executable.
/// Returns: parsed command or usage error before files are opened.
pub fn parse(args: &[String]) -> Result<Command, &'static str> {
    match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["--help"] | ["-h"] => Ok(Command::Help),
        ["render-unit", source, dest, root] => Ok(Command::Render {
            source: (*source).into(),
            dest: (*dest).into(),
            root: (*root).into(),
        }),
        ["kitty-defaults-remove", path] => Ok(Command::DefaultsRemove((*path).into())),
        ["kitty-filter", path, state @ ("on" | "off"), comment, legacy_comment, mapping, legacy_prefix, mapping_prefix] => {
            Ok(Command::Filter {
                path: (*path).into(),
                enabled: *state == "on",
                text: FilterText {
                    comment: (*comment).into(),
                    legacy_comment: (*legacy_comment).into(),
                    mapping: (*mapping).into(),
                    legacy_prefix: (*legacy_prefix).into(),
                    mapping_prefix: (*mapping_prefix).into(),
                },
            })
        }
        _ => Err(USAGE),
    }
}

/// Read UTF-8 and preserve the original Python universal newline behavior.
/// Parameters: path - source file to read.
/// Returns: normalized text or file/encoding error.
fn read_text(path: &Path) -> Result<String, String> {
    fs::read_to_string(path)
        .map(|text| text.replace("\r\n", "\n").replace('\r', "\n"))
        .map_err(|error| error.to_string())
}

/// Split a normalized config with the original str.splitlines separators.
/// Parameters: text - complete normalized config.
/// Returns: lines without a synthetic final empty row.
fn config_lines(text: &str) -> Vec<String> {
    if text.is_empty() {
        return Vec::new();
    }
    let separator = |character| {
        matches!(
            character,
            '\n' | '\x0b'
                | '\x0c'
                | '\x1c'
                | '\x1d'
                | '\x1e'
                | '\u{0085}'
                | '\u{2028}'
                | '\u{2029}'
        )
    };
    let mut lines = text
        .split(separator)
        .map(str::to_string)
        .collect::<Vec<_>>();
    if text.ends_with(separator) {
        lines.pop();
    }
    lines
}

/// Apply Python's whitespace-only test to config blank rows.
/// Parameters: line - one config row.
/// Returns: whether the row is empty after whitespace stripping.
fn blank(line: &str) -> bool {
    line.chars()
        .all(|character| character.is_whitespace() || matches!(character, '\x1c'..='\x1f'))
}

/// Write reconciled lines with the original trailing-newline convention.
/// Parameters: path - existing or caller-created destination; lines - complete kept rows.
/// Returns: empty stdout or write failure.
fn write_lines(path: &Path, lines: &[String]) -> Result<String, String> {
    let text = lines.join("\n");
    let text = text.trim_end_matches('\n');
    let output = if text.is_empty() {
        String::new()
    } else {
        format!("{text}\n")
    };
    fs::write(path, output).map_err(|error| error.to_string())?;
    Ok(String::new())
}

/// Reconcile only the managed conditional and legacy apostrophe prefixes.
/// Parameters: path - config; enabled - on/off selection; text - caller's existing mapping constants.
/// Returns: empty stdout or filesystem error, preserving unrelated rows.
fn kitty_filter(path: &Path, enabled: bool, text: &FilterText) -> Result<String, String> {
    let lines = if path.exists() {
        config_lines(&read_text(path)?)
    } else {
        Vec::new()
    };
    let mut kept: Vec<String> = Vec::new();
    for line in lines {
        if line.starts_with(&text.legacy_prefix) || line.starts_with(&text.mapping_prefix) {
            if kept
                .last()
                .is_some_and(|line| line == &text.comment || line == &text.legacy_comment)
            {
                kept.pop();
            }
            while kept.last().is_some_and(|line| blank(line)) {
                kept.pop();
            }
        } else {
            kept.push(line);
        }
    }
    if enabled {
        if kept.is_empty() {
            kept.push("# Managed by linux_configuration_setup.".into());
        }
        while kept.last().is_some_and(|line| blank(line)) {
            kept.pop();
        }
        kept.extend([String::new(), text.comment.clone(), text.mapping.clone()]);
    }
    if let Some(parent) = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    write_lines(path, &kept)
}

/// Remove the original managed default prefixes and directly preceding comments.
/// Parameters: path - existing Kitty config.
/// Returns: empty stdout or filesystem error.
fn kitty_defaults_remove(path: &Path) -> Result<String, String> {
    let mut kept: Vec<String> = Vec::new();
    for line in config_lines(&read_text(path)?) {
        if [
            "confirm_os_window_close",
            "map ctrl+backspace",
            "wayland_titlebar_color",
        ]
        .iter()
        .any(|prefix| line.starts_with(prefix))
        {
            while kept.last().is_some_and(|line| line.starts_with('#')) {
                kept.pop();
            }
            while kept.last().is_some_and(|line| blank(line)) {
                kept.pop();
            }
        } else {
            kept.push(line);
        }
    }
    write_lines(path, &kept)
}

/// Render every literal installer-root token without interpreting shell syntax.
/// Parameters: source - unit template; dest - caller's temp file; root - physical checkout path.
/// Returns: empty stdout or read/write error.
fn render_unit(source: &Path, dest: &Path, root: &str) -> Result<String, String> {
    let text = read_text(source)?.replace("@LCS_SCRIPT_DIR@", root);
    fs::write(dest, text).map_err(|error| error.to_string())?;
    Ok(String::new())
}

/// Delegate parsed arguments to file operation owners.
/// Parameters: command - parsed operation/operands.
/// Returns: stdout or operation failure.
pub fn execute(command: Command) -> Result<String, String> {
    match command {
        Command::Help => Ok(format!("{USAGE}\n")),
        Command::Render { source, dest, root } => render_unit(&source, &dest, &root),
        Command::DefaultsRemove(path) => kitty_defaults_remove(&path),
        Command::Filter {
            path,
            enabled,
            text,
        } => kitty_filter(&path, enabled, &text),
    }
}
