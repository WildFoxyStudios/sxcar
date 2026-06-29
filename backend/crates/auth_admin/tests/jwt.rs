//! Integration tests for [`auth_admin::jwt`].
//!
//! Spec AD1 T6: HS256, aud=admin, exp validation, cross-audience rejection.

use jsonwebtoken::{encode, EncodingKey, Header};
use uuid::Uuid;

use auth_admin::jwt::{issue, verify, StaffClaims};
use auth_admin::AuthError;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn test_secret() -> &'static str {
    "test-hs256-secret-key-must-be-at-least-32-bytes"
}

fn test_permissions() -> Vec<String> {
    vec!["read:users".into(), "write:users".into()]
}

fn now_ts() -> usize {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as usize
}

// ---------------------------------------------------------------------------
// issue + verify roundtrip
// ---------------------------------------------------------------------------

#[test]
fn issue_and_verify_roundtrip() {
    let secret = test_secret();
    let staff_id = Uuid::new_v4();
    let role = "admin";
    let perms = test_permissions();
    let ttl = 28800;

    let token = issue(secret, staff_id, role, &perms, ttl).expect("issue");
    let claims = verify(secret, &token).expect("verify");

    assert_eq!(claims.sub, staff_id.to_string(), "sub debe ser staff_id");
    assert_eq!(claims.aud, "admin", "aud debe ser 'admin'");
    assert_eq!(claims.staff_role, role, "staff_role debe coincidir");
    assert_eq!(claims.permissions, perms, "permissions deben coincidir");
    // exp = iat + ttl
    assert_eq!(
        claims.exp - claims.iat,
        ttl as usize,
        "exp - iat debe ser ttl_secs"
    );
    // jti debe ser un UUID valido
    assert!(
        Uuid::parse_str(&claims.jti).is_ok(),
        "jti debe ser UUID valido"
    );
}

// ---------------------------------------------------------------------------
// Rechazo por audience incorrecta
// ---------------------------------------------------------------------------

#[test]
fn verify_rejects_wrong_audience() {
    let secret = test_secret();
    let staff_id = Uuid::new_v4();
    let now = now_ts();
    let ttl = 28800;

    // Creamos manualmente un token con aud="app" (no "admin").
    let app_claims = StaffClaims {
        sub: staff_id.to_string(),
        aud: "app".to_string(),
        staff_role: "admin".to_string(),
        permissions: test_permissions(),
        iat: now,
        exp: now + ttl,
        jti: Uuid::new_v4().to_string(),
    };

    let token = encode(
        &Header::default(),
        &app_claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .expect("encode app-audience token");

    let result = verify(secret, &token);
    assert!(
        matches!(result, Err(AuthError::JwtInvalid(ref msg)) if msg.contains("aud") || msg.contains("Audience")),
        "esperado JwtInvalid por audience, got {result:?}"
    );
}

// ---------------------------------------------------------------------------
// Rechazo por token expirado
// ---------------------------------------------------------------------------

#[test]
fn verify_rejects_expired_token() {
    let secret = test_secret();
    let staff_id = Uuid::new_v4();
    // TTL negativo => token expira en el pasado (1 h atras).
    // Leeway en verify es 30 s, asi que 3600 s en el pasado es seguro.
    let token = issue(secret, staff_id, "admin", &test_permissions(), -3600)
        .expect("issue con TTL negativo");

    let result = verify(secret, &token);
    assert!(
        matches!(result, Err(AuthError::JwtInvalid(_))),
        "esperado JwtInvalid por expiracion, got {result:?}"
    );
}

// ---------------------------------------------------------------------------
// Rechazo por firma alterada
// ---------------------------------------------------------------------------

#[test]
fn verify_rejects_tampered_signature() {
    let secret = test_secret();
    let staff_id = Uuid::new_v4();
    let token = issue(secret, staff_id, "admin", &test_permissions(), 28800)
        .expect("issue");

    // Alteramos el ultimo caracter de la firma.
    let tampered = {
        let mut chars: Vec<char> = token.chars().collect();
        let last = chars.len() - 1;
        chars[last] = if chars[last] == 'a' { 'b' } else { 'a' };
        chars.into_iter().collect::<String>()
    };

    let result = verify(secret, &tampered);
    assert!(
        matches!(result, Err(AuthError::JwtInvalid(_))),
        "esperado JwtInvalid por firma alterada, got {result:?}"
    );
}

// ---------------------------------------------------------------------------
// Rechazo por token vacio
// ---------------------------------------------------------------------------

#[test]
fn verify_rejects_empty_token() {
    let secret = test_secret();
    let result = verify(secret, "");
    assert!(
        matches!(result, Err(AuthError::JwtInvalid(_))),
        "esperado JwtInvalid para token vacio, got {result:?}"
    );
}

// ---------------------------------------------------------------------------
// Claims incluyen jti y permissions
// ---------------------------------------------------------------------------

#[test]
fn claims_include_jti_and_permissions() {
    let secret = test_secret();
    let staff_id = Uuid::new_v4();
    let perms = vec![
        "read:users".into(),
        "write:users".into(),
        "read:reports".into(),
    ];

    let token = issue(secret, staff_id, "superadmin", &perms, 3600).expect("issue");
    let claims = verify(secret, &token).expect("verify");

    // jti es UUID unico
    let jti_parsed = Uuid::parse_str(&claims.jti).expect("jti debe ser UUID valido");
    assert_ne!(jti_parsed, Uuid::nil(), "jti no debe ser nil UUID");

    // permissions incluyen las tres otorgadas
    assert!(
        claims.permissions.contains(&"read:users".into()),
        "debe contener read:users"
    );
    assert!(
        claims.permissions.contains(&"write:users".into()),
        "debe contener write:users"
    );
    assert!(
        claims.permissions.contains(&"read:reports".into()),
        "debe contener read:reports"
    );

    // jti es diferente entre emisiones
    let token2 = issue(secret, staff_id, "superadmin", &perms, 3600).expect("issue second");
    let claims2 = verify(secret, &token2).expect("verify second");
    assert_ne!(
        claims.jti, claims2.jti,
        "cada token debe tener jti unico"
    );
}
