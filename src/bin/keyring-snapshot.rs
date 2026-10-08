//! Native keyring snapshot entrypoint; diagnostics never include secret values.

#[path = "../keyring.rs"]
mod keyring;

/// Parse raw arguments and delegate to the native secret operation owners.
/// Parameters: none; process tokens provide complete operands.
/// Returns: None; exits zero on success, one for operations, two for usage.
fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let status = match keyring::parse(&args) {
        Ok(command) => match keyring::execute(command) {
            Ok(output) => {
                print!("{output}");
                0
            }
            Err(error) => {
                eprintln!("keyring-snapshot: {error}");
                1
            }
        },
        Err(error) => {
            eprintln!("{error}");
            2
        }
    };
    std::process::exit(status);
}
