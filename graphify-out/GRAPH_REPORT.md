# Graph Report - backend/crates  (2026-07-06)

## Corpus Check
- 117 files · ~86,955 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1461 nodes · 3217 edges · 72 communities (67 shown, 5 thin omitted)
- Extraction: 81% EXTRACTED · 19% INFERRED · 0% AMBIGUOUS · INFERRED: 612 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Chat & Messaging System|Chat & Messaging System]]
- [[_COMMUNITY_Auth & Security Layer|Auth & Security Layer]]
- [[_COMMUNITY_API Core & Routing|API Core & Routing]]
- [[_COMMUNITY_Profile & Grid Handlers|Profile & Grid Handlers]]
- [[_COMMUNITY_Health & DB Tests|Health & DB Tests]]
- [[_COMMUNITY_Billing & Stories Content|Billing & Stories Content]]
- [[_COMMUNITY_Enterprise DB Models|Enterprise DB Models]]
- [[_COMMUNITY_Admin Moderation Handlers|Admin Moderation Handlers]]
- [[_COMMUNITY_Admin Enterprise Config|Admin Enterprise Config]]
- [[_COMMUNITY_Admin Auth & TOTP|Admin Auth & TOTP]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]

## God Nodes (most connected - your core abstractions)
1. `connect()` - 77 edges
2. `AuditTarget` - 39 edges
3. `app()` - 37 edges
4. `migrate()` - 35 edges
5. `AuditJustification` - 29 edges
6. `setup_test_db()` - 29 edges
7. `rbac_check()` - 27 edges
8. `teardown_test_db()` - 27 edges
9. `test_app()` - 19 edges
10. `register_two()` - 19 edges

## Surprising Connections (you probably didn't know these)
- `send_campaign()` --calls--> `get_campaign()`  [INFERRED]
  api/src/admin/handlers_enterprise.rs → db/src/enterprise.rs
- `send_campaign()` --calls--> `get_campaign_target_user_ids()`  [INFERRED]
  api/src/admin/handlers_enterprise.rs → db/src/enterprise.rs
- `send_campaign()` --calls--> `update_campaign_status()`  [INFERRED]
  api/src/admin/handlers_enterprise.rs → db/src/enterprise.rs
- `register()` --calls--> `valid_email()`  [INFERRED]
  api/src/auth/handlers.rs → px_core/src/validation.rs
- `register()` --calls--> `valid_password()`  [INFERRED]
  api/src/auth/handlers.rs → px_core/src/validation.rs

## Communities (72 total, 5 thin omitted)

### Community 0 - "Chat & Messaging System"
Cohesion: 0.05
Nodes (57): add_group_member(), AddMemberRequest, classify_kind(), conversation_id_for_message(), ConversationJson, ConversationRow, create_conversation(), create_group() (+49 more)

### Community 1 - "Auth & Security Layer"
Cohesion: 0.08
Nodes (47): AuthDeps, AuthUser, AccessClaims, cfg(), expired_fails(), issue_access(), issue_and_verify(), JwtConfig (+39 more)

### Community 2 - "API Core & Routing"
Cohesion: 0.07
Nodes (49): allowed_origins(), blocks_unknown_origin(), cors_layer(), is_localhost(), preflight_allows_configured_prod_origin(), preflight_allows_localhost_origin(), test_app(), app() (+41 more)

### Community 3 - "Profile & Grid Handlers"
Cohesion: 0.05
Nodes (39): get_user(), do_seed(), seed_inner(), seed_service(), SeedResponse, find_nearby_users(), NearbyUserRow, upsert_location() (+31 more)

### Community 4 - "Health & DB Tests"
Cohesion: 0.15
Nodes (46): Health, connect(), ping(), connect_and_ping_succeeds(), test_db_url(), add_looking_for(), add_primary_photo(), add_tribe() (+38 more)

### Community 5 - "Billing & Stories Content"
Cohesion: 0.1
Nodes (38): BillingError, accepts_msgpack(), respond(), respond_defaults_to_json(), respond_returns_msgpack_when_accepted(), respond_with_status(), respond_with_status_uses_custom_status(), test_body() (+30 more)

### Community 6 - "Enterprise DB Models"
Cohesion: 0.05
Nodes (13): AbuseRuleRow, ApiKeyRow, CampaignRow, CmsContentRow, ConfigVersionRow, ExperimentRow, get_campaign(), get_campaign_target_user_ids() (+5 more)

### Community 7 - "Admin Moderation Handlers"
Cohesion: 0.05
Nodes (27): ActionRequest, dossier_to_json(), legal_export(), LegalExportRequest, ListAuditQuery, ListCsamQuery, ListDataRequestsQuery, ListPhotosQuery (+19 more)

### Community 8 - "Admin Enterprise Config"
Cohesion: 0.09
Nodes (36): CampaignSendRequest, ConfigHistoryQuery, create_campaign(), create_legal_doc(), CreateApiKeyRequest, CreateApiKeyResponse, CreateCampaignRequest, CreateLegalDocRequest (+28 more)

### Community 9 - "Admin Auth & TOTP"
Cohesion: 0.13
Nodes (32): build_totp(), current_code(), decode_base32(), decrypt_secret(), encrypt_secret(), gen_secret(), verify_code(), current_totp_code() (+24 more)

### Community 10 - "Community 10"
Cohesion: 0.08
Nodes (28): add_phrase(), add_place(), add_saved_phrase(), add_saved_place(), AddPhraseReq, AddPlaceReq, boost_active(), create_boost() (+20 more)

### Community 11 - "Community 11"
Cohesion: 0.09
Nodes (30): add_favorite(), AddFavoriteRequest, block_user(), BlockJson, BlockListResponse, BlockRow, BlockUserRequest, check_not_blocked() (+22 more)

### Community 12 - "Community 12"
Cohesion: 0.13
Nodes (25): gen(), hash(), is_valid_format(), verify(), add_feature_to_plan_and_list(), add_price_for_country(), current_totp_code(), get_auth() (+17 more)

### Community 13 - "Community 13"
Cohesion: 0.11
Nodes (26): issue_pair(), login(), logout(), oauth(), refresh(), reset_password(), add_auth_identity(), create_user() (+18 more)

### Community 14 - "Community 14"
Cohesion: 0.18
Nodes (26): list_users(), base_url(), setup_test_db(), teardown_test_db(), with_db(), count_users_by_status(), find_user_by_id(), search_users() (+18 more)

### Community 15 - "Community 15"
Cohesion: 0.12
Nodes (24): AuditJustification, AuditTarget, activate_user(), ban_user(), delete_plan_feature(), create_api_key(), create_webhook(), delete_cms_content() (+16 more)

### Community 16 - "Community 16"
Cohesion: 0.22
Nodes (27): current_totp_code(), get_auth(), get_auth_body(), grant_entitlement_adds_row(), legal_export_returns_dossier(), list_data_requests_filters_by_status(), login_and_get_jwt(), place_and_release_legal_hold() (+19 more)

### Community 17 - "Community 17"
Cohesion: 0.12
Nodes (25): client_ip(), list_audit(), login(), two_factor(), AuditRow, create_session(), find_active_session(), find_staff_by_email() (+17 more)

### Community 18 - "Community 18"
Cohesion: 0.11
Nodes (17): FcmClient, from_env_parses_json(), JwtClaims, send_without_token_returns_error(), TokenResponse, default_notification_prefs(), DeviceRow, get_notification_prefs() (+9 more)

### Community 19 - "Community 19"
Cohesion: 0.27
Nodes (26): approve_photo_changes_status(), current_totp_code(), get_auth(), list_csam_hits_and_report_to_authority(), list_pending_photos_returns_only_pending(), list_reports_returns_open_reports(), login_and_get_jwt(), post() (+18 more)

### Community 20 - "Community 20"
Cohesion: 0.08
Nodes (10): decimal_string_to_minor(), list_plans(), ListPlansResponse, PlanDto, PriceDto, CountryConfigRow, list_plan_prices(), PlanFeatureRow (+2 more)

### Community 21 - "Community 21"
Cohesion: 0.11
Nodes (19): amz_timestamps(), cfg(), create_photo(), CreatePhotoReq, CreatePhotoRes, get_url(), GetUrlQuery, GetUrlRes (+11 more)

### Community 22 - "Community 22"
Cohesion: 0.27
Nodes (25): activate_user_reactivates(), ban_user_bans_and_returns_200(), current_totp_code(), force_logout_revokes_tokens(), get(), get_auth(), get_user_by_id_returns_full_profile(), get_user_returns_404_for_nonexistent() (+17 more)

### Community 23 - "Community 23"
Cohesion: 0.09
Nodes (19): list_entitlements(), manage_entitlement(), export_data(), AccessEventRow, build_legal_dossier(), ConsentRow, DataRequestRow, DeviceRow (+11 more)

### Community 24 - "Community 24"
Cohesion: 0.11
Nodes (21): AlertRow, create_intent(), CreateIntentReq, delete_intent(), get_idle_reminder(), get_idle_reminder_hours(), IntentRow, list_active_sessions() (+13 more)

### Community 25 - "Community 25"
Cohesion: 0.22
Nodes (23): analytics_overview_returns_counts(), current_totp_code(), delete_auth(), delete_flag_removes(), get_auth(), list_config_has_maintenance_mode(), list_flags_returns_seeded(), login_and_get_jwt() (+15 more)

### Community 26 - "Community 26"
Cohesion: 0.39
Nodes (22): block_deletes_conversation(), block_user_and_list(), blocked_user_not_in_grid(), delete_(), favorite_and_unfavorite(), get(), insert_profile(), post() (+14 more)

### Community 27 - "Community 27"
Cohesion: 0.32
Nodes (21): empty_message_is_rejected(), get(), heartbeat_sets_last_seen(), list_profile_views_empty_initially(), post(), profile_health_get_then_put(), profile_health_invalid_date_is_400(), put() (+13 more)

### Community 28 - "Community 28"
Cohesion: 0.33
Nodes (20): get_auth(), get_other_profile_by_id_returns_public_data(), get_other_profile_returns_404_for_nonexistent(), get_own_profile_returns_full_data(), get_public_filters_show_age_when_false(), get_public_filters_show_role_when_false(), get_public_filters_show_tribes_when_false(), get_public_strips_all_six_show_flags_simultaneously() (+12 more)

### Community 29 - "Community 29"
Cohesion: 0.14
Nodes (17): create_story(), CreateStoryRequest, CreateStoryResponse, delete_story(), get_active_stories(), get_connected_user_ids(), get_story_by_id(), has_viewed() (+9 more)

### Community 30 - "Community 30"
Cohesion: 0.18
Nodes (18): OAuthReq, PhoneReq, register(), resend_email(), reset_request(), ResetReq, ResetRequestReq, send_phone_code() (+10 more)

### Community 31 - "Community 31"
Cohesion: 0.12
Nodes (11): approve_photo(), reject_photo(), resolve_report(), review_report(), create_moderation_action(), CsamRow, find_report_by_id(), PhotoModerationRow (+3 more)

### Community 32 - "Community 32"
Cohesion: 0.35
Nodes (18): create_api_key_returns_full_key_once_and_list_hides_it(), create_campaign_draft_and_list(), create_webhook_and_list(), current_totp_code(), get_auth(), list_experiments_empty_by_default(), login_and_get_jwt(), post_auth() (+10 more)

### Community 33 - "Community 33"
Cohesion: 0.29
Nodes (18): current_totp_code(), login_with_nonexistent_email_returns_401(), login_with_valid_credentials_returns_mfa_token(), login_with_wrong_password_returns_401(), logout_with_valid_session_returns_204(), post(), post_auth(), seed_staff() (+10 more)

### Community 34 - "Community 34"
Cohesion: 0.17
Nodes (13): apple_verify_aud_mismatch_rejected(), apple_verify_bad_base64_rejected(), apple_verify_invalid_jwt_rejected(), apple_verify_valid_token_succeeds(), dev_verifier_parses(), DevOAuthVerifier, OAuthIdentity, OAuthVerifier (+5 more)

### Community 35 - "Community 35"
Cohesion: 0.37
Nodes (17): add_group_member(), create_group(), creator_can_rename(), delete_req(), get(), list_group_members(), non_creator_cannot_rename(), non_member_cannot_send_to_group() (+9 more)

### Community 36 - "Community 36"
Cohesion: 0.12
Nodes (16): AddPhotosReq, AddPhotosResponse, AlbumPhotoResponse, create(), create_album(), CreateAlbumReq, CreateAlbumResponse, delete() (+8 more)

### Community 37 - "Community 37"
Cohesion: 0.12
Nodes (15): analytics_overview(), delete_flag(), list_config(), list_flags(), upsert_config(), upsert_flag(), AnalyticsOverview, AppConfigEntry (+7 more)

### Community 38 - "Community 38"
Cohesion: 0.18
Nodes (8): auth_limiter(), in_memory_allows_different_ips_independently(), in_memory_blocks_after_capacity(), in_memory_refills_over_time(), InMemoryRateLimiter, Limiter, limiter_from_env_creates_in_memory_when_no_redis(), RedisRateLimiter

### Community 39 - "Community 39"
Cohesion: 0.32
Nodes (16): get_auth(), get_first_price_id_for(), get_no_auth(), me_returns_active_subscription_after_purchase(), plans_list_includes_features_and_prices(), plans_list_returns_seeded_paid_tiers(), plans_list_sorted_by_tier_then_code(), post_auth() (+8 more)

### Community 40 - "Community 40"
Cohesion: 0.24
Nodes (15): current_totp_code(), get(), login_and_get_jwt(), post(), post_auth(), seed_staff(), setup_kek_env(), staff_password_hash() (+7 more)

### Community 41 - "Community 41"
Cohesion: 0.18
Nodes (14): add_photos(), add_photos_to_album(), AlbumPhotoRow, AlbumRow, get(), get_album(), get_album_photos(), PhotoRow (+6 more)

### Community 42 - "Community 42"
Cohesion: 0.46
Nodes (13): boost_create_and_check_active(), delete(), get(), phrases_add_list_delete_reorder(), places_add_list_delete(), post(), put(), register_one() (+5 more)

### Community 43 - "Community 43"
Cohesion: 0.45
Nodes (12): bad_secret_401(), expiration_downgrades(), post_no_auth(), post_webhook(), rc_event(), register_user(), repeated_renewal_does_not_stack(), test_app() (+4 more)

### Community 44 - "Community 44"
Cohesion: 0.37
Nodes (12): get(), get_preferences_requires_auth(), post(), put(), register_device_and_list(), register_device_requires_auth(), register_user(), test_app() (+4 more)

### Community 45 - "Community 45"
Cohesion: 0.17
Nodes (5): AppleAppSiteAssociation, Applinks, AssetLink, Detail, Target

### Community 46 - "Community 46"
Cohesion: 0.26
Nodes (4): chat_broker_from_env_creates_in_memory_when_no_redis(), ChatBroker, in_memory_publish_and_subscribe_roundtrip(), RedisChatBroker

### Community 47 - "Community 47"
Cohesion: 0.18
Nodes (4): DevNotifier, Notifier, smtp_from_env_some_when_set(), SmtpNotifier

### Community 48 - "Community 48"
Cohesion: 0.44
Nodes (11): get_json(), non_sender_unsend_rejected(), post_json(), register_user(), setup_conversation_with_message(), test_app(), test_db_url(), unique_email() (+3 more)

### Community 49 - "Community 49"
Cohesion: 0.45
Nodes (10): cleanup_env(), env_lock(), from_env_malformed_base64_returns_error(), from_env_missing_env_returns_kek_missing(), from_env_with_custom_version(), from_env_with_valid_base64_key_succeeds(), from_env_wrong_key_length_returns_error(), set_kek_env() (+2 more)

### Community 50 - "Community 50"
Cohesion: 0.45
Nodes (9): call_get_url(), get_url_bad_kind_returns_400(), get_url_empty_key_returns_400(), get_url_no_r2_returns_503(), get_url_traversal_key_returns_400(), get_url_unauth_returns_401(), register_token(), test_app() (+1 more)

### Community 51 - "Community 51"
Cohesion: 0.56
Nodes (10): create_conversation_and_list(), ephemeral_photo_view_once(), get(), list_conversations_empty(), post(), send_message_and_retrieve(), test_app(), test_db_url() (+2 more)

### Community 52 - "Community 52"
Cohesion: 0.2
Nodes (4): age(), is_adult(), valid_email(), valid_password()

### Community 53 - "Community 53"
Cohesion: 0.29
Nodes (8): format_rfc3339(), grant_revenuecat_subscription(), my_subscription(), MySubscriptionResponse, revoke_revenuecat_subscription(), constant_time_eq(), map_plan_code(), revenuecat_webhook()

### Community 54 - "Community 54"
Cohesion: 0.42
Nodes (9): generate_blur_handles_large_image(), generate_blur_invalid_input_returns_err(), generate_blur_produces_valid_jpeg(), generate_blur_rendition(), generate_clear_thumbnail(), generate_clear_thumbnail_invalid_input_returns_err(), generate_clear_thumbnail_max_320px(), jpeg_dimensions() (+1 more)

### Community 55 - "Community 55"
Cohesion: 0.44
Nodes (9): claims_include_jti_and_permissions(), issue_and_verify_roundtrip(), now_ts(), test_permissions(), test_secret(), verify_rejects_empty_token(), verify_rejects_expired_token(), verify_rejects_tampered_signature() (+1 more)

### Community 56 - "Community 56"
Cohesion: 0.5
Nodes (7): issue(), issue_returns_ok_with_valid_input(), issue_sets_correct_aud(), perms(), secret(), StaffClaims, verify()

### Community 57 - "Community 57"
Cohesion: 0.32
Nodes (6): get_preferences(), PrivacyPreferences, PrivacyPrefError, row_to_prefs(), update_preferences(), UpdatePrivacyPreferences

### Community 60 - "Community 60"
Cohesion: 0.33
Nodes (5): AlbumResponse, list(), list_albums(), list_shared_albums(), shared()

### Community 61 - "Community 61"
Cohesion: 0.33
Nodes (5): CodeReq, LoginReq, RefreshReq, RegisterReq, TokenPair

### Community 63 - "Community 63"
Cohesion: 0.5
Nodes (4): format_rfc3339(), simulate_purchase(), SimulatePurchaseReq, SubscriptionDto

## Knowledge Gaps
- **216 isolated node(s):** `CreateAlbumReq`, `ListAlbumsResponse`, `CreateAlbumResponse`, `UpdateAlbumReq`, `AddPhotosReq` (+211 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `connect()` connect `Health & DB Tests` to `Chat & Messaging System`, `Auth & Security Layer`, `API Core & Routing`, `Billing & Stories Content`, `Admin Auth & TOTP`, `Community 12`, `Community 14`, `Community 16`, `Community 19`, `Community 22`, `Community 25`, `Community 26`, `Community 27`, `Community 28`, `Community 32`, `Community 33`, `Community 35`, `Community 39`, `Community 40`, `Community 42`, `Community 43`, `Community 44`, `Community 48`, `Community 50`, `Community 51`?**
  _High betweenness centrality (0.219) - this node is a cross-community bridge._
- **Why does `setup_test_db()` connect `Community 14` to `Community 17`, `API Core & Routing`, `Health & DB Tests`, `Community 13`?**
  _High betweenness centrality (0.133) - this node is a cross-community bridge._
- **Why does `update_user_status()` connect `Community 15` to `Community 13`, `Community 14`, `Community 31`?**
  _High betweenness centrality (0.095) - this node is a cross-community bridge._
- **Are the 76 inferred relationships involving `connect()` (e.g. with `relay_passthrough_broadcasts_to_members()` and `main()`) actually correct?**
  _`connect()` has 76 INFERRED edges - model-reasoned connections that need verification._
- **Are the 37 inferred relationships involving `AuditTarget` (e.g. with `review_report()` and `resolve_report()`) actually correct?**
  _`AuditTarget` has 37 INFERRED edges - model-reasoned connections that need verification._
- **Are the 36 inferred relationships involving `app()` (e.g. with `seed_service()` and `cors_layer()`) actually correct?**
  _`app()` has 36 INFERRED edges - model-reasoned connections that need verification._
- **Are the 34 inferred relationships involving `migrate()` (e.g. with `relay_passthrough_broadcasts_to_members()` and `main()`) actually correct?**
  _`migrate()` has 34 INFERRED edges - model-reasoned connections that need verification._