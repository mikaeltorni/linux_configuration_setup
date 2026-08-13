//! `lcs-tools` — installer helpers for linux-configuration-setup.
//!
//! ```text
//! CURRENT="['a']" lcs-tools append dash-to-panel@x
//! CURRENT="['a']" lcs-tools remove dash-to-panel@x
//! CURRENT="['a']" lcs-tools contains a
//! lcs-tools patch-metadata metadata.json 46 9999
//! ```

mod gsettings_strv;
mod logging;
mod patch_metadata;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("patch-metadata") => patch_metadata::run(&args),
        Some("append") | Some("remove") | Some("contains") => gsettings_strv::run(&args),
        _ => gsettings_strv::run(&args),
    };
    std::process::exit(code);
}
