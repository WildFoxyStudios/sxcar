# Task 3 Report: Share profile option lists between wizard and edit_profile

## Summary

Extracted all duplicated profile option lists into a single shared file to eliminate the drift between the onboarding wizard and the edit-profile screen.

## Files created

- `apps/app/lib/src/models/profile_options.dart` — single source of truth containing all 12 shared const lists: `kHivStatusOptions`, `kGenderOptions`, `kTribeOptions`, `kRelationshipStatusOptions`, `kPositionOptions`, `kLookingForOptions`, `kEthnicityOptions`, `kPronounsOptions`, `kBodyTypeOptions`, `kMeetAtOptions`, `kTagOptions`, `kRoleOptions`.

## Files modified

- `apps/app/lib/src/features/edit_profile_screen.dart` — removed `_hivStatusOptions` and `_tribeOptions`; imports `kHivStatusOptions` and `kTribeOptions` from `profile_options.dart`.
- `apps/app/lib/src/features/edit_profile/sheets.dart` — removed 10 private `_k*` const lists; imports public `k*` variants from `profile_options.dart`.
- `apps/app/lib/src/onboarding/cards/tribes_card.dart` — removed `_options`; uses `kTribeOptions`.
- `apps/app/lib/src/onboarding/cards/looking_for_card.dart` — removed `_options`; uses `kLookingForOptions`.
- `apps/app/lib/src/onboarding/cards/relationship_status_card.dart` — removed `_options`; uses `kRelationshipStatusOptions`.
- `apps/app/lib/src/onboarding/cards/ethnicity_card.dart` — removed `_options`; uses `kEthnicityOptions`.
- `apps/app/lib/src/onboarding/cards/position_preference_card.dart` — removed `_options`; uses `kPositionOptions`.
- `apps/app/lib/src/onboarding/cards/gender_position_card.dart` — removed `_genders` and inline `['Top', 'Bottom', 'Versatile', 'Side']` list; uses `kGenderOptions` and `kPositionOptions`.

## In-scope exclusions (by design)

- `vaccines_card.dart` / `vaccines_screen.dart` — lists differ in casing and values (wizard uses display labels, edit-profile uses backend keys).
- `practices_card.dart` / `practices_screen.dart` — lists differ in language and content.

## Test results

474 passed, 1 skipped, 1 failed (pre-existing `pin_screen_test.dart` failure — unrelated to this change).

## Commit

```
d9d6e659 refactor(app): share profile option lists between wizard and edit_profile
```
