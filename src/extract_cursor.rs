//! Extract a Windows CUR image as an RGBA PNG for `xcursorgen`.
//!
//! ```text
//! lcs-tools extract-cursor INPUT.cur OUTPUT.png [SIZE]
//! ```
//!
//! Prints the scaled hotspot as `X Y` on stdout.

use std::fs;
use std::path::Path;

use image::imageops::FilterType;
use image::{ImageFormat, RgbaImage};

use crate::logging;

/// Directory entry for one image inside a CUR file.
#[derive(Clone, Copy, Debug)]
pub struct CursorEntry {
    pub width: u32,
    pub height: u32,
    pub hotspot_x: u16,
    pub hotspot_y: u16,
}

/// Return metadata for the largest image in a Windows CUR file.
///
/// # Parameters
/// - `data`: Raw CUR bytes.
pub fn read_largest_cursor_entry(data: &[u8]) -> Result<CursorEntry, String> {
    if data.len() < 6 {
        return Err("cursor file is too small".into());
    }
    let reserved = u16::from_le_bytes([data[0], data[1]]);
    let cursor_type = u16::from_le_bytes([data[2], data[3]]);
    let entry_count = u16::from_le_bytes([data[4], data[5]]) as usize;
    if reserved != 0 || cursor_type != 2 {
        return Err("input is not a Windows CUR file".into());
    }
    if entry_count < 1 || data.len() < 6 + entry_count * 16 {
        return Err("cursor file has no complete image entries".into());
    }
    let mut best: Option<CursorEntry> = None;
    for index in 0..entry_count {
        let offset = 6 + index * 16;
        let width_byte = data[offset];
        let height_byte = data[offset + 1];
        let hotspot_x = u16::from_le_bytes([data[offset + 4], data[offset + 5]]);
        let hotspot_y = u16::from_le_bytes([data[offset + 6], data[offset + 7]]);
        let entry = CursorEntry {
            width: if width_byte == 0 {
                256
            } else {
                u32::from(width_byte)
            },
            height: if height_byte == 0 {
                256
            } else {
                u32::from(height_byte)
            },
            hotspot_x,
            hotspot_y,
        };
        let better = best.is_none_or(|cur| {
            entry.width * entry.height > cur.width * cur.height
                || (entry.width * entry.height == cur.width * cur.height && entry.width > cur.width)
        });
        if better {
            best = Some(entry);
        }
    }
    best.ok_or_else(|| "cursor file has no complete image entries".into())
}

fn decode_cur_rgba(data: &[u8]) -> Result<RgbaImage, String> {
    let mut ico = data.to_vec();
    if ico.len() >= 4 {
        ico[2] = 1;
        ico[3] = 0;
    }
    let dyn_img = image::load_from_memory_with_format(&ico, ImageFormat::Ico)
        .map_err(|e| format!("could not decode CUR image: {e}"))?;
    Ok(dyn_img.to_rgba8())
}

/// Extract the largest CUR frame, optionally resize, and write a PNG.
///
/// # Parameters
/// - `cursor_path`: Input `.cur` file.
/// - `output_path`: Destination PNG.
/// - `size`: Optional square output size. `None` keeps the source width.
///
/// # Returns
/// Scaled hotspot `(x, y)`.
pub fn extract_cursor(
    cursor_path: &Path,
    output_path: &Path,
    size: Option<u32>,
) -> Result<(u32, u32), String> {
    let data = fs::read(cursor_path).map_err(|e| e.to_string())?;
    let entry = read_largest_cursor_entry(&data)?;
    let mut image = decode_cur_rgba(&data)?;
    let output_size = size.unwrap_or(image.width());
    if output_size == 0 {
        return Err("output size must be positive".into());
    }
    let scale_x = f64::from(output_size) / f64::from(entry.width);
    let scale_y = f64::from(output_size) / f64::from(entry.height);
    let hotspot_x = (f64::from(entry.hotspot_x) * scale_x).round() as u32;
    let hotspot_y = (f64::from(entry.hotspot_y) * scale_y).round() as u32;
    if image.width() != output_size || image.height() != output_size {
        image = image::imageops::resize(&image, output_size, output_size, FilterType::Lanczos3);
    }
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    image
        .save_with_format(output_path, ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    logging::info(format!(
        "Saved cursor PNG to {} at {output_size}x{output_size}",
        output_path.display()
    ));
    Ok((hotspot_x, hotspot_y))
}

/// CLI: `extract-cursor INPUT.cur OUTPUT.png [SIZE]`.
pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 || args.len() > 4 || args[0] != "extract-cursor" {
        logging::error("Usage: lcs-tools extract-cursor <input.cur> <output.png> [size]");
        eprintln!("Usage: lcs-tools extract-cursor <input.cur> <output.png> [size]");
        return 2;
    }
    let size = match args.get(3) {
        None => None,
        Some(s) => match s.parse::<u32>() {
            Ok(n) => Some(n),
            Err(_) => {
                logging::error(format!("invalid output size: {s}"));
                eprintln!("Error: output size must be a positive integer");
                return 2;
            }
        },
    };
    logging::info(format!(
        "Running cursor extraction from {} to {}",
        args[1], args[2]
    ));
    match extract_cursor(Path::new(&args[1]), Path::new(&args[2]), size) {
        Ok((x, y)) => {
            println!("{x} {y}");
            0
        }
        Err(err) => {
            logging::error(err.clone());
            eprintln!("Error: {err}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_cur_header() {
        let data = [0u8, 0, 1, 0, 0, 0];
        assert!(read_largest_cursor_entry(&data).is_err());
    }
}
