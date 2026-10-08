//! Native desktop configuration file entrypoint.

#[path = "../desktop_config.rs"]
mod desktop_config;

/// Parse raw arguments and delegate to the responsible file operation.
/// Parameters: none; command tokens come from the process.
/// Returns: None; exits zero, operation error one or usage error two.
fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let status = match desktop_config::parse(&args) {
        Ok(command) => match desktop_config::execute(command) {
            Ok(output) => {
                print!("{output}");
                0
            }
            Err(error) => {
                eprintln!("desktop-config: {error}");
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
