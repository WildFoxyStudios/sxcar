use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
pub struct FilterOptions {
    pub tribes: Vec<&'static str>,
    pub looking_for: Vec<&'static str>,
    pub body_types: Vec<&'static str>,
    pub relationship_statuses: Vec<&'static str>,
    pub genders: Vec<&'static str>,
    pub positions: Vec<&'static str>,
}

/// `GET /meta/filters`
///
/// Returns the enumerations for filter dropdowns so they can be updated
/// without an app release. The app fetches this on startup and caches,
/// falling back to hardcoded lists if the API is unreachable.
pub async fn get_filters() -> Json<FilterOptions> {
    Json(FilterOptions {
        tribes: vec![
            "Bear",
            "Otter",
            "Twink",
            "Jock",
            "Daddy",
            "Geek",
            "Muscle",
            "Chub",
            "Leather",
            "Trans",
            "Queer",
        ],
        looking_for: vec![
            "Chat",
            "Dates",
            "Friends",
            "Networking",
            "Relationship",
            "Right Now",
        ],
        body_types: vec![
            "Slim",
            "Average",
            "Athletic",
            "Muscular",
            "Curvy",
            "Stocky",
            "Large",
        ],
        relationship_statuses: vec![
            "Single",
            "Dating",
            "Partnered",
            "Married",
            "Open Relationship",
        ],
        genders: vec!["Man", "Woman", "Non-Binary", "Trans Man", "Trans Woman"],
        positions: vec!["Top", "Bottom", "Versatile", "Side"],
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_filters() -> FilterOptions {
        FilterOptions {
            tribes: vec!["Bear", "Otter", "Twink", "Jock", "Daddy", "Geek"],
            looking_for: vec!["Chat", "Dates", "Friends"],
            body_types: vec!["Slim", "Average", "Athletic"],
            relationship_statuses: vec!["Single", "Dating"],
            genders: vec!["Man", "Woman"],
            positions: vec!["Top", "Bottom"],
        }
    }

    #[test]
    fn filter_options_contains_all_categories() {
        let f = make_filters();
        assert!(!f.tribes.is_empty());
        assert!(!f.looking_for.is_empty());
        assert!(!f.body_types.is_empty());
        assert!(!f.relationship_statuses.is_empty());
        assert!(!f.genders.is_empty());
        assert!(!f.positions.is_empty());
    }

    #[test]
    fn filter_options_serializes_to_expected_json() {
        let f = make_filters();
        let json: serde_json::Value = serde_json::to_value(f).unwrap();

        assert_eq!(json["tribes"][0], "Bear");
        assert!(json["looking_for"].as_array().unwrap().iter().any(|v| v == "Friends"));
        assert_eq!(json["body_types"].as_array().unwrap().len(), 3);
        assert_eq!(json["relationship_statuses"].as_array().unwrap().len(), 2);
        assert_eq!(json["genders"].as_array().unwrap().len(), 2);
        assert_eq!(json["positions"].as_array().unwrap().len(), 2);
    }
}
