use axum::Json;
use serde::Serialize;

fn apple_team_id() -> String {
    std::env::var("APPLE_TEAM_ID").unwrap_or_else(|_| "CHANGE_ME_APPLE_TEAM_ID".into())
}

fn android_sha256() -> String {
    std::env::var("ANDROID_SHA256_FINGERPRINT").unwrap_or_else(|_| android_sha256().into())
}

/// `GET /.well-known/apple-app-site-association`
///
/// Serves the Apple App Site Association file for Universal Links.
/// Configure via env: APPLE_TEAM_ID (default: placeholder).
#[derive(Serialize)]
pub struct AppleAppSiteAssociation {
    pub applinks: Applinks,
}

#[derive(Serialize)]
pub struct Applinks {
    pub apps: Vec<String>,
    pub details: Vec<Detail>,
}

#[derive(Serialize)]
pub struct Detail {
    #[serde(rename = "appID")]
    pub app_id: String,
    pub paths: Vec<String>,
}

pub async fn apple_site_association() -> Json<AppleAppSiteAssociation> {
    Json(AppleAppSiteAssociation {
        applinks: Applinks {
            apps: vec![],
            details: vec![Detail {
                app_id: format!("{}.com.proyectox.app", apple_team_id()).to_string(),
                paths: vec!["/profile/*".to_string(), "/chat/*".to_string(), "/".to_string()],
            }],
        },
    })
}

/// `GET /.well-known/assetlinks.json`
///
/// Serves the Android Asset Links file for App Links.
/// Always returns JSON (no content-negotiation).
#[derive(Serialize)]
pub struct AssetLink {
    pub relation: Vec<String>,
    pub target: Target,
}

#[derive(Serialize)]
pub struct Target {
    pub namespace: String,
    pub package_name: String,
    #[serde(rename = "sha256_cert_fingerprints")]
    pub sha256_cert_fingerprints: Vec<String>,
}

pub async fn assetlinks() -> Json<Vec<AssetLink>> {
    Json(vec![AssetLink {
        relation: vec!["delegate_permission/common.handle_all_urls".to_string()],
        target: Target {
            namespace: "android_app".to_string(),
            package_name: "com.proyectox.app".to_string(),
            sha256_cert_fingerprints: vec![android_sha256().to_string()],
        },
    }])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_site_association_serializes_correctly() {
        let aasa = AppleAppSiteAssociation {
            applinks: Applinks {
                apps: vec![],
                details: vec![Detail {
                    app_id: format!("{}.com.proyectox.app", apple_team_id()).to_string(),
                    paths: vec![
                        "/profile/*".to_string(),
                        "/chat/*".to_string(),
                        "/".to_string(),
                    ],
                }],
            },
        };
        let json: serde_json::Value = serde_json::to_value(aasa).unwrap();
        assert_eq!(json["applinks"]["apps"], serde_json::json!([]));
        assert_eq!(
            json["applinks"]["details"][0]["appID"],
            format!("{}.com.proyectox.app", apple_team_id())
        );
        assert_eq!(
            json["applinks"]["details"][0]["paths"],
            serde_json::json!(["/profile/*", "/chat/*", "/"])
        );
    }

    #[test]
    fn assetlinks_serializes_correctly() {
        let links = vec![AssetLink {
            relation: vec!["delegate_permission/common.handle_all_urls".to_string()],
            target: Target {
                namespace: "android_app".to_string(),
                package_name: "com.proyectox.app".to_string(),
                sha256_cert_fingerprints: vec![android_sha256().to_string()],
            },
        }];
        let json: serde_json::Value = serde_json::to_value(links).unwrap();
        let entry = &json[0];
        assert_eq!(
            entry["relation"],
            serde_json::json!(["delegate_permission/common.handle_all_urls"])
        );
        assert_eq!(entry["target"]["namespace"], "android_app");
        assert_eq!(entry["target"]["package_name"], "com.proyectox.app");
        assert_eq!(
            entry["target"]["sha256_cert_fingerprints"],
            serde_json::json!([android_sha256()])
        );
    }
}
