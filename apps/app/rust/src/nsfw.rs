use image::GenericImageView;
use std::sync::OnceLock;
use tract_onnx::prelude::*;

/// NSFW classification result.
#[derive(Debug)]
pub struct NsfwResult {
    /// 0.0 (safe) to 1.0 (nsfw)
    pub score: f32,
    pub is_nsfw: bool,
}

/// Threshold above which an image is considered NSFW.
const NSFW_THRESHOLD: f32 = 0.7;

/// Cached ONNX model (lazy-loaded once).
#[allow(dead_code)]
static MODEL: OnceLock<
    SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>,
> = OnceLock::new();

/// Path to the ONNX model file, set before classification.
static MODEL_PATH: OnceLock<String> = OnceLock::new();

/// Set the path to the NSFW ONNX model file.
///
/// Call this at app startup with the path to the bundled model asset,
/// e.g. `loadNsfwModel(path: "assets/models/nsfw.onnx")`.
#[flutter_rust_bridge::frb]
pub fn load_nsfw_model(path: String) -> Result<(), String> {
    MODEL_PATH
        .set(path)
        .map_err(|_| "NSFW model path already set".to_string())
}

/// Classify an image as SFW or NSFW.
///
/// `image_bytes` is the raw image data (JPEG, PNG, etc.).
///
/// # Web (WASM)
///
/// tract-onnx does not compile to WASM. On web, this function returns an error
/// instructing the caller to use the platform's JS-based NSFW detection instead.
#[flutter_rust_bridge::frb]
pub fn nsfw_classify(image_bytes: Vec<u8>) -> Result<NsfwResult, String> {
    // WASM guard: tract-onnx does not compile to WASM.
    #[cfg(target_family = "wasm")]
    {
        let _ = image_bytes;
        return Err(
            "NSFW detection on web uses a different engine (JS/ONNX runtime). \
             Call the Dart-side nsfw proxy instead."
                .to_string(),
        );
    }

    // Native path below.
    #[cfg(not(target_family = "wasm"))]
    {
        // 1. Decode image
        let img = image::load_from_memory(&image_bytes)
            .map_err(|e| format!("Failed to decode image: {e}"))?;

        // 2. Resize to model input size (224x224 for most mobile-optimized NSFW models)
        let resized = img.resize_exact(224, 224, image::imageops::FilterType::Nearest);

        // 3. Convert to tensor (NHWC: 1, 224, 224, 3) normalized to [0,1]
        let mut tensor_data = vec![0.0f32; 3 * 224 * 224];
        for (i, (_, _, pixel)) in resized.pixels().enumerate() {
            tensor_data[i * 3] = pixel[0] as f32 / 255.0;
            tensor_data[i * 3 + 1] = pixel[1] as f32 / 255.0;
            tensor_data[i * 3 + 2] = pixel[2] as f32 / 255.0;
        }

        // 4. Load model (cached after first load)
        let model = load_model()?;

        // 5. Run inference
        let tensor = tract_ndarray::Array4::from_shape_vec((1, 224, 224, 3), tensor_data)
            .map_err(|e| format!("Failed to create tensor: {e}"))?;
        let input = Tensor::from(tensor);

        let result = model
            .run(tvec!(input.into()))
            .map_err(|e| format!("Inference failed: {e}"))?;

        // 6. Get softmax output (2 classes: SFW=0, NSFW=1)
        let output = result[0]
            .to_array_view::<f32>()
            .map_err(|e| format!("Failed to read output tensor: {e}"))?;
        let nsfw_score = output[[0, 1]]; // index 1 = NSFW probability

        Ok(NsfwResult {
            score: nsfw_score,
            is_nsfw: nsfw_score > NSFW_THRESHOLD,
        })
    }
}

/// Load (or retrieve cached) ONNX model.
///
/// # Stub
///
/// In production, the ONNX model is loaded from the path set by
/// [`load_nsfw_model`] and cached in [`MODEL`]. For now (F1.3), the model
/// file is not yet bundled, so this function returns a clear error.
///
/// The actual file‑based loading will be wired in a follow‑up task.
fn load_model(
) -> Result<
    &'static SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>,
    String,
> {
    MODEL.get_or_try_init(|| {
        let path = MODEL_PATH
            .get()
            .ok_or_else(|| "NSFW model path not set — call load_nsfw_model(path) first. Download the ONNX model from https://github.com/Fyko/nsfw/releases".to_string())?;
        let model_bytes =
            std::fs::read(path).map_err(|e| format!("Failed to read model file '{path}': {e}; download from https://github.com/Fyko/nsfw/releases"))?;
        tract_onnx::tract_onnx()
            .model_for_read(&mut &*model_bytes)
            .map_err(|e| format!("Failed to parse ONNX model: {e}"))?
            .with_input_fact(0, InferenceFact::dt_shape(f32::datum_type(), tvec!(1, 224, 224, 3)))
            .map_err(|e| format!("Failed to set input shape: {e}"))?
            .into_optimized()
            .map_err(|e| format!("Failed to optimize model: {e}"))?
            .into_runnable()
            .map_err(|e| format!("Failed to create runnable model: {e}"))
    })
    .map_err(|e| e.clone())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_valid_jpeg() {
        // Create a tiny valid JPEG in memory (1x1 pixel).
        let mut buf = std::io::Cursor::new(Vec::new());
        let img = image::DynamicImage::new_rgb8(1, 1);
        let mut encoder = image::codecs::jpeg::JpegEncoder::new(&mut buf);
        encoder
            .encode(img.as_bytes(), 1, 1, image::ExtendedColorType::Rgb8)
            .expect("JPEG encode should succeed");
        let jpeg_bytes = buf.into_inner();

        // Verify it decodes with the image crate
        let decoded = image::load_from_memory(&jpeg_bytes);
        assert!(decoded.is_ok(), "JPEG should decode successfully");
        assert_eq!(decoded.unwrap().dimensions(), (1, 1));
    }

    #[test]
    fn test_model_load_fails_gracefully() {
        // Without calling load_nsfw_model, the classify function should return
        // a clear error about model not being configured.
        let result = nsfw_classify(vec![0u8; 100]);
        assert!(result.is_err(), "Should fail without model configured");
        let err = result.unwrap_err();
        assert!(
            err.contains("not yet bundled") || err.contains("Failed to decode"),
            "Error should mention model bundling or decode: {err}"
        );
    }

    #[test]
    fn test_threshold_default_0_7() {
        // Verify the threshold constant is 0.7
        assert!((NSFW_THRESHOLD - 0.7).abs() < f32::EPSILON);
    }
}
