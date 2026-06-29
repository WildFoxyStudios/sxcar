use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, ExtendedColorType};

/// Decode, resize proportionally to fit within `max_width x max_height`
/// (keeping aspect ratio), encode as JPEG quality 85, return bytes.
#[flutter_rust_bridge::frb(sync)]
pub fn resize_for_upload(image_bytes: Vec<u8>, max_width: u32, max_height: u32) -> Vec<u8> {
    let img = match image::load_from_memory(&image_bytes) {
        Ok(img) => img,
        Err(_) => return image_bytes,
    };

    let (w, h) = (img.width(), img.height());

    // Don't upscale — return original if already within bounds
    if w <= max_width && h <= max_height {
        return image_bytes;
    }

    // Calculate proportional dimensions that fit within the box
    let ratio = (max_width as f64 / w as f64).min(max_height as f64 / h as f64);
    let new_w = (w as f64 * ratio).round() as u32;
    let new_h = (h as f64 * ratio).round() as u32;

    let resized = img.resize_exact(
        new_w.max(1),
        new_h.max(1),
        image::imageops::FilterType::Lanczos3,
    );

    encode_jpeg(&resized, 85)
}

/// Resize to `size x size` square (crop to fit), JPEG quality 80.
#[flutter_rust_bridge::frb(sync)]
pub fn create_thumbnail(image_bytes: Vec<u8>, size: u32) -> Vec<u8> {
    let img = match image::load_from_memory(&image_bytes) {
        Ok(img) => img,
        Err(_) => return image_bytes,
    };

    // resize_to_fill resizes to cover the given dimensions, cropping as needed
    let thumb = img.resize_to_fill(size, size, image::imageops::FilterType::Lanczos3);

    encode_jpeg(&thumb, 80)
}

/// Remove EXIF metadata by decoding and re-encoding as JPEG (quality 92).
#[flutter_rust_bridge::frb(sync)]
pub fn strip_exif(image_bytes: Vec<u8>) -> Vec<u8> {
    let img = match image::load_from_memory(&image_bytes) {
        Ok(img) => img,
        Err(_) => return image_bytes,
    };

    encode_jpeg(&img, 92)
}

// ---------------------------------------------------------------------------
// Internal helper
// ---------------------------------------------------------------------------

fn encode_jpeg(img: &DynamicImage, quality: u8) -> Vec<u8> {
    let mut buf: Vec<u8> = Vec::new();
    let mut encoder = JpegEncoder::new_with_quality(&mut buf, quality);
    let rgb = img.to_rgb8();
    let _ = encoder.encode(
        rgb.as_raw(),
        rgb.width(),
        rgb.height(),
        ExtendedColorType::Rgb8,
    );
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::RgbImage;

    /// Helper: create a solid-colour RgbImage of given dimensions.
    fn make_test_image(width: u32, height: u32) -> Vec<u8> {
        let mut img = RgbImage::new(width, height);
        for pixel in img.pixels_mut() {
            pixel[0] = 200; // R
            pixel[1] = 100; // G
            pixel[2] = 50;  // B
        }
        let mut buf = Vec::new();
        let mut encoder = JpegEncoder::new_with_quality(&mut buf, 95);
        let _ =
            encoder.encode(img.as_raw(), width, height, ExtendedColorType::Rgb8);
        buf
    }

    #[test]
    fn test_resize_for_upload_reduces_size() {
        let input = make_test_image(800, 600);
        assert!(input.len() > 100, "input too small for a meaningful test");

        let result = resize_for_upload(input.clone(), 200, 200);
        assert!(
            result.len() < input.len(),
            "expected resized output ({}) < input ({})",
            result.len(),
            input.len()
        );

        // Verify it's valid JPEG
        assert_eq!(&result[..2], &[0xFF, 0xD8], "not a valid JPEG");
    }

    #[test]
    fn test_resize_for_upload_within_bounds_is_unchanged() {
        let input = make_test_image(100, 100);
        let result = resize_for_upload(input.clone(), 1024, 768);
        assert_eq!(result, input, "should return original when already within bounds");
    }

    #[test]
    fn test_create_thumbnail_produces_square() {
        let input = make_test_image(400, 300);
        let result = create_thumbnail(input, 50);
        assert_eq!(&result[..2], &[0xFF, 0xD8], "not a valid JPEG");

        // Re-decode and verify dimensions
        let decoded = image::load_from_memory(&result).expect("valid JPEG");
        assert_eq!(decoded.width(), 50);
        assert_eq!(decoded.height(), 50);
    }

    #[test]
    fn test_strip_exif_preserves_image() {
        let input = make_test_image(320, 240);
        let result = strip_exif(input.clone());
        assert_eq!(&result[..2], &[0xFF, 0xD8], "not a valid JPEG");

        // Decode and verify same dimensions
        let decoded = image::load_from_memory(&result).expect("valid JPEG");
        assert_eq!(decoded.width(), 320);
        assert_eq!(decoded.height(), 240);
    }

    #[test]
    fn test_invalid_bytes_returned_as_is() {
        let bad = b"not an image".to_vec();
        assert_eq!(resize_for_upload(bad.clone(), 100, 100), bad);
        assert_eq!(create_thumbnail(bad.clone(), 50), bad);
        assert_eq!(strip_exif(bad.clone()), bad);
    }
}
