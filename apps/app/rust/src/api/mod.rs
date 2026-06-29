pub mod imaging;

use crate::nsfw::{self, NsfwResult};
use px_core::validation::valid_email;

#[flutter_rust_bridge::frb(sync)]
pub fn validate_email(email: String) -> bool {
    valid_email(&email)
}

/// Set the path to the NSFW ONNX model file.
#[flutter_rust_bridge::frb]
pub fn load_nsfw_model(path: String) -> Result<(), String> {
    nsfw::load_nsfw_model(path)
}

/// Classify an image as SFW or NSFW.
#[flutter_rust_bridge::frb]
pub fn nsfw_classify(image_bytes: Vec<u8>) -> Result<NsfwResult, String> {
    nsfw::nsfw_classify(image_bytes)
}
