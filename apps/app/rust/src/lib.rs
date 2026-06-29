mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
use px_core::validation::valid_email;

#[flutter_rust_bridge::frb(sync)]
pub fn validate_email(email: String) -> bool {
    valid_email(&email)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
