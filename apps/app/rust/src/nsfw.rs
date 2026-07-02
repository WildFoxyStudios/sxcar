use image::GenericImageView;
use std::sync::OnceLock;

// tract-onnx is pure Rust and cross-compiles to Android via cargo-ndk.
// Only skip on WASM where the filesystem is not accessible.
#[cfg(not(target_family = "wasm"))]
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

// ---------------------------------------------------------------------------
// Discovered model spec (introspected from assets/models/nsfw.onnx)
//
// Producer : tf2onnx 1.17.0  (converted from nsfwjs TF2 SavedModel)
// Input    : name="input", shape=[1, 224, 224, 3], dtype=float32, layout=NHWC
// Output   : shape=[1, 5], dtype=float32
//            indices → classes: [drawings=0, hentai=1, neutral=2, porn=3, sexy=4]
// NSFW score = (hentai + porn + 0.5 * sexy) clamped to [0, 1]
// ---------------------------------------------------------------------------

/// Cached compiled ONNX model (lazy-loaded once per process).
/// Available on native platforms (Android + desktop); skipped on WASM.
#[cfg(not(target_family = "wasm"))]
static MODEL: OnceLock<
    SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>,
> = OnceLock::new();

/// Absolute path to the ONNX model file, set once before first inference.
static MODEL_PATH: OnceLock<String> = OnceLock::new();

/// Store the path to the NSFW ONNX model file.
///
/// Must be called before [`nsfw_classify`].  The Dart side extracts the
/// bundled asset to a temp path and passes that path here once at startup.
/// Returns `Err` if the path was already set (harmless — ignore it).
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
/// On WASM, returns an error — the Dart caller should skip the check on web.
/// On failure, the Dart caller should fail-open (allow the upload) and log.
#[flutter_rust_bridge::frb]
pub fn nsfw_classify(image_bytes: Vec<u8>) -> Result<NsfwResult, String> {
    #[cfg(target_family = "wasm")]
    {
        let _ = image_bytes;
        return Err(
            "NSFW detection on web uses a JS-side engine; call the Dart proxy instead."
                .to_string(),
        );
    }

    #[allow(unreachable_code)]
    #[cfg(not(target_family = "wasm"))]
    {
        // 1. Decode image
        let img = image::load_from_memory(&image_bytes)
            .map_err(|e| format!("Failed to decode image: {e}"))?;

        // 2. Resize to 224 × 224 (model input size)
        let resized = img.resize_exact(224, 224, image::imageops::FilterType::Nearest);

        // 3. Build NHWC tensor [1, 224, 224, 3], values in [0, 1]
        let mut tensor_data = vec![0.0f32; 224 * 224 * 3];
        for (i, (_, _, pixel)) in resized.pixels().enumerate() {
            tensor_data[i * 3]     = pixel[0] as f32 / 255.0;
            tensor_data[i * 3 + 1] = pixel[1] as f32 / 255.0;
            tensor_data[i * 3 + 2] = pixel[2] as f32 / 255.0;
        }

        // 4. Load (or retrieve cached) model
        let model = load_model()?;

        // 5. Run inference
        let tensor = tract_ndarray::Array4::from_shape_vec((1, 224, 224, 3), tensor_data)
            .map_err(|e| format!("Failed to create tensor: {e}"))?;
        let input: Tensor = tensor.into();

        let result = model
            .run(tvec!(input.into()))
            .map_err(|e| format!("Inference failed: {e}"))?;

        // 6. Extract NSFW score from output
        // Output shape [1, 5]: indices [drawings, hentai, neutral, porn, sexy]
        let output = result[0]
            .to_array_view::<f32>()
            .map_err(|e| format!("Failed to read output tensor: {e}"))?;

        let shape = output.shape();
        let nsfw_score = if shape.len() >= 2 && shape[1] == 5 {
            // 5-class nsfwjs model
            let hentai = output[[0, 1]];
            let porn   = output[[0, 3]];
            let sexy   = output[[0, 4]];
            (hentai + porn + 0.5 * sexy).clamp(0.0, 1.0)
        } else if shape.len() >= 2 && shape[1] >= 2 {
            // Fallback 2-class [normal, nsfw]
            output[[0, 1]]
        } else {
            return Err(format!("Unexpected output shape: {shape:?}"));
        };

        Ok(NsfwResult {
            score: nsfw_score,
            is_nsfw: nsfw_score > NSFW_THRESHOLD,
        })
    }
}

/// Load (or retrieve cached) compiled ONNX model.
///
/// The model is loaded from the path set by [`load_nsfw_model`] and compiled
/// once; subsequent calls return a reference to the cached plan.
#[cfg(not(target_family = "wasm"))]
fn load_model(
) -> Result<
    &'static SimplePlan<TypedFact, Box<dyn TypedOp>, Graph<TypedFact, Box<dyn TypedOp>>>,
    String,
> {
    if let Some(model) = MODEL.get() {
        return Ok(model);
    }
    let path = MODEL_PATH
        .get()
        .ok_or_else(|| "NSFW model path not set — call load_nsfw_model(path) first".to_string())?;
    let model = tract_onnx::onnx()
        .model_for_path(path)
        .map_err(|e| format!("Failed to parse ONNX model at '{path}': {e}"))?
        .with_input_fact(
            0,
            InferenceFact::dt_shape(f32::datum_type(), tvec!(1, 224, 224, 3)),
        )
        .map_err(|e| format!("Failed to set input shape: {e}"))?
        .into_optimized()
        .map_err(|e| format!("Failed to optimize model: {e}"))?
        .into_runnable()
        .map_err(|e| format!("Failed to create runnable model: {e}"))?;
    let _ = MODEL.set(model);
    Ok(MODEL.get().unwrap())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    /// Generate a solid-colour JPEG in memory (no file I/O required).
    fn make_solid_jpeg(r: u8, g: u8, b: u8, w: u32, h: u32) -> Vec<u8> {
        use image::codecs::jpeg::JpegEncoder;
        use image::{ExtendedColorType, ImageBuffer, Rgb};
        let img: ImageBuffer<Rgb<u8>, Vec<u8>> =
            ImageBuffer::from_pixel(w, h, Rgb([r, g, b]));
        let mut buf = std::io::Cursor::new(Vec::new());
        let mut encoder = JpegEncoder::new(&mut buf);
        encoder
            .encode(img.as_raw(), w, h, ExtendedColorType::Rgb8)
            .expect("JPEG encode should succeed");
        buf.into_inner()
    }

    #[test]
    fn test_decode_valid_jpeg() {
        let jpeg = make_solid_jpeg(200, 150, 100, 8, 8);
        let decoded = image::load_from_memory(&jpeg);
        assert!(decoded.is_ok(), "JPEG should decode successfully");
        assert_eq!(decoded.unwrap().dimensions(), (8, 8));
    }

    #[test]
    fn test_model_load_fails_gracefully() {
        // 100 zero bytes are neither a valid image nor an ONNX file.
        // Expected outcomes depending on test-execution order:
        //   • MODEL_PATH not yet set → "not set" error
        //   • MODEL_PATH set by test_real_inference (runs in parallel) →
        //     model loads fine, then image decode fails → "Failed to decode"
        let result = nsfw_classify(vec![0u8; 100]);
        assert!(result.is_err(), "Should fail on bad input");
        let err = result.unwrap_err();
        assert!(
            err.contains("not set") || err.contains("Failed to decode"),
            "Unexpected error message: {err}"
        );
    }

    #[test]
    fn test_threshold_default_0_7() {
        assert!((NSFW_THRESHOLD - 0.7).abs() < f32::EPSILON);
    }

    /// Real-inference smoke test: loads assets/models/nsfw.onnx via tract,
    /// classifies a neutral grey image, and asserts score ∈ [0, 1].
    ///
    /// Cargo sets cwd = crate root (apps/app/rust/) so the relative path
    /// `../assets/models/nsfw.onnx` resolves to apps/app/assets/models/nsfw.onnx.
    #[test]
    fn test_real_inference_neutral_image() {
        let model_path = "../assets/models/nsfw.onnx";

        // Set model path — ignore "already set" from parallel test runs.
        let _ = load_nsfw_model(model_path.to_string());

        // Neutral image: solid grey 64 × 64.
        let jpeg = make_solid_jpeg(128, 128, 128, 64, 64);

        let result = nsfw_classify(jpeg);
        match result {
            Ok(r) => {
                assert!(
                    (0.0..=1.0).contains(&r.score),
                    "score out of [0,1] range: {}",
                    r.score
                );
                assert!(
                    !r.is_nsfw,
                    "neutral grey image must not be flagged NSFW, score={}",
                    r.score
                );
            }
            Err(e) => {
                panic!(
                    "Real inference failed: {e}\n\
                     If error mentions 'quantized ops', report BLOCKED — \
                     tract cannot load this quantized model and ort is needed."
                );
            }
        }
    }
}
