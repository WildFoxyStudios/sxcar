use image::imageops::FilterType;
use image::{GenericImageView, ImageFormat};

/// Generate a blurred version of image bytes.
/// Max dimension: 320px, Gaussian blur sigma=15.0.
/// Returns JPEG bytes.
pub fn generate_blur_rendition(image_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let img = image::load_from_memory(image_bytes).map_err(|e| format!("decode: {e}"))?;
    let (w, h) = img.dimensions();
    let ratio = 320.0 / w.max(h) as f64;
    let small = img.resize(
        (w as f64 * ratio) as u32,
        (h as f64 * ratio) as u32,
        FilterType::Lanczos3,
    );
    let blurred = small.blur(15.0);
    let mut buf = std::io::Cursor::new(Vec::new());
    blurred
        .write_to(&mut buf, ImageFormat::Jpeg)
        .map_err(|e| format!("encode: {e}"))?;
    Ok(buf.into_inner())
}

/// Generate a clear thumbnail (no blur). Max 320px.
pub fn generate_clear_thumbnail(image_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let img = image::load_from_memory(image_bytes).map_err(|e| format!("decode: {e}"))?;
    let (w, h) = img.dimensions();
    let ratio = 320.0 / w.max(h) as f64;
    let thumb = img.resize(
        (w as f64 * ratio) as u32,
        (h as f64 * ratio) as u32,
        FilterType::Lanczos3,
    );
    let mut buf = std::io::Cursor::new(Vec::new());
    thumb
        .write_to(&mut buf, ImageFormat::Jpeg)
        .map_err(|e| format!("encode: {e}"))?;
    Ok(buf.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::DynamicImage;
    use image::GenericImageView;

    /// Create a small test image (red pixel, 200x150) as JPEG bytes.
    fn test_jpeg_bytes() -> Vec<u8> {
        let mut img = DynamicImage::new_rgba8(200, 150);
        // Fill with red pixels
        for pixel in img.as_mut_rgba8().unwrap().pixels_mut() {
            *pixel = image::Rgba([255u8, 0, 0, 255]);
        }
        let mut buf = std::io::Cursor::new(Vec::new());
        img.write_to(&mut buf, ImageFormat::Jpeg)
            .expect("encode test image");
        buf.into_inner()
    }

    /// Reload JPEG bytes and return dimensions. Panics if invalid.
    fn jpeg_dimensions(bytes: &[u8]) -> (u32, u32) {
        let img = image::load_from_memory(bytes).expect("valid jpeg");
        img.dimensions()
    }

    #[test]
    fn generate_blur_produces_valid_jpeg() {
        let original = test_jpeg_bytes();
        let blurred = generate_blur_rendition(&original).expect("blur should succeed");
        assert!(!blurred.is_empty(), "blur output should not be empty");
        // Must decode as valid JPEG
        let (w, h) = jpeg_dimensions(&blurred);
        assert!(w <= 320 && h <= 320, "blur dimensions ({w}x{h}) exceed 320px max");
    }

    #[test]
    fn generate_clear_thumbnail_max_320px() {
        let original = test_jpeg_bytes();
        let thumb = generate_clear_thumbnail(&original).expect("thumbnail should succeed");
        assert!(!thumb.is_empty(), "thumbnail output should not be empty");
        // Must decode as valid JPEG with max 320px on longest side
        let (w, h) = jpeg_dimensions(&thumb);
        assert!(w <= 320 && h <= 320, "thumbnail dimensions ({w}x{h}) exceed 320px max");
        // Aspect ratio should be preserved (200:150 = 4:3)
        // 320 max side: width=320, height=240 for 200x150 source
        assert_eq!(w, 320, "expected width 320, got {w}");
        assert_eq!(h, 240, "expected height 240, got {h}");
    }

    #[test]
    fn generate_blur_handles_large_image() {
        // 4000x3000 image (larger than max 320px)
        let mut img = DynamicImage::new_rgba8(4000, 3000);
        for pixel in img.as_mut_rgba8().unwrap().pixels_mut() {
            *pixel = image::Rgba([128u8, 64, 192, 255]);
        }
        let mut buf = std::io::Cursor::new(Vec::new());
        img.write_to(&mut buf, ImageFormat::Jpeg)
            .expect("encode large test image");
        let bytes = buf.into_inner();

        let blurred = generate_blur_rendition(&bytes).expect("large image blur should succeed");
        assert!(!blurred.is_empty(), "blur output should not be empty");
        let (w, h) = jpeg_dimensions(&blurred);
        assert!(w <= 320 && h <= 320, "large blur dimensions ({w}x{h}) exceed 320px max");
        // 4000:3000 = 4:3, max 320 -> width=320, height=240
        assert_eq!(w, 320, "expected width 320, got {w}");
        assert_eq!(h, 240, "expected height 240, got {h}");
    }

    #[test]
    fn generate_blur_invalid_input_returns_err() {
        let result = generate_blur_rendition(b"not an image");
        assert!(result.is_err(), "invalid input should return error");
    }

    #[test]
    fn generate_clear_thumbnail_invalid_input_returns_err() {
        let result = generate_clear_thumbnail(b"not an image");
        assert!(result.is_err(), "invalid input should return error");
    }
}
