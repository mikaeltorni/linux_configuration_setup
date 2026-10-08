//! Command entry for the persistent GDM X11 policy.

#[path = "../gdm.rs"]
mod gdm;

use gdm::{parse_gdm_args, run_gdm};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let parsed = match parse_gdm_args(&args) {
        Ok(parsed) => parsed,
        Err(message) => {
            eprintln!("{message}");
            return ExitCode::from(2);
        }
    };
    match run_gdm(&parsed) {
        Ok(message) => {
            if !message.is_empty() {
                println!("{message}");
            }
            ExitCode::SUCCESS
        }
        Err(message) if message.is_empty() => ExitCode::from(1),
        Err(message) => {
            eprintln!("{message}");
            ExitCode::from(1)
        }
    }
}
