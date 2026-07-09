# Vibra — brand & design system

**Product name: Vibra.** Visual identity: **Halo** (electric duotone).
Original — **not derived from any third-party app.**
Source of truth = this document + the tokens in `apps/app/lib/src/theme/app_theme.dart`.

The app launcher name (Android `android:label`, iOS `CFBundleDisplayName`) and
the `MaterialApp` title are all "Vibra".

## Positioning
Electric duotone for a queer, location-based social/dating app. Energetic and
nocturnal, but trust-forward (privacy & safety are first-class). Stands out in a
store full of black-and-neutral apps.

## Palette (canonical tokens)

| Role | Token | Hex | Notes |
|------|-------|-----|-------|
| Background | `kBg` | `#0B0E14` | blue-black base |
| Surface | `kSurface` | `#151A24` | cards, sheets |
| Surface elevated | `kSurfaceElevated` | `#1E2430` | |
| Chip | `kChip` | `#1E2430` | segmented / chips |
| Divider | `kDivider` | `#2A3140` | |
| **Brand primary** | `kBrandPrimary` | `#00E0C6` | teal — dark text over it |
| Brand primary light | `kBrandPrimaryLight` | `#33E8D2` | gradients/hovers |
| **Brand secondary** | `kBrandSecondary` | `#FF3D8B` | magenta — white text over it |
| Accent "Pulse" | `kAccentPulse` | `#2FD07A` | "go/active" (was Boost) |
| Accent "Glow" | `kAccentGlow` | `#FF3D8B` | urgency (was Right-Now) |
| Text primary | `kText` | `#EAF6FF` | cool white |
| Text secondary | `kTextSecondary` | `#8A94A6` | |
| Text tertiary/muted | `kTextTertiary` | `#5A6373` | |
| Online | `kOnline` | `#2FD07A` | presence dot |
| Success | `kSuccess` | `#2FD07A` | |
| Danger/error | `kError` / `kBadgeRed` | `#FF4D5E` | |

**Contrast rules:** dark text (`kBg`) over teal primary; white text over magenta
secondary; `kText` over all surfaces.

## Naming
- Tokens use **functional, brand-neutral** names (`kBrandPrimary`, `kSurface`,
  `kSuccess`…). The former third-party-flavoured feature-colour names
  (`kBoost`, `kRightNow`, `kYellow`) were removed/renamed to
  `kAccentPulse`, `kAccentGlow`, `kBrandPrimary`.
- Premium tiers use original names: **Glow / Pulse / Aura** (free tier = base).
  (Backend `plan_code` values are internal and unchanged; only display names differ.)

## Spacing & radius
4/8pt spacing. Radius tokens: `kRadiusCard` 12, `kRadiusInput` 10, `kRadiusChip` 20.
Page padding `kPadPage` 16.

## Still to do (product decisions)
- **Logo / wordmark** for "Vibra" (name is decided).
- App icon + discreet-icon variants in the Halo palette.
- Marketing site palette alignment.
