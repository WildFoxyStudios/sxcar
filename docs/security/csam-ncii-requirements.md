# CSAM / NCII detection — requirements (ÉPICA B, launch-blocking)

**Status:** NOT implemented. This document records what is required so it can be
wired when the accounts/approvals exist. Per the completitud spec (§2), automated
detection of Child Sexual Abuse Material (CSAM) and Non-Consensual Intimate Imagery
(NCII) in the media-upload pipeline is **mandatory before public launch** — it is a
legal requirement (US 18 U.S.C. §2258A reporting, EU DSA, Apple/Google store policy)
and an ethical one.

> This is the single remaining launch-blocker identified in the spec. Everything
> else can ship without it; this cannot.

## What must exist before launch

1. **Hash-matching against known-CSAM databases** on every image/video upload,
   BEFORE the media is retrievable by any other user.
2. **NCII hash-matching** (StopNCII) so victims can pre-emptively block their
   intimate images.
3. **Mandatory reporting pipeline**: a confirmed CSAM match must (a) block the
   upload, (b) preserve evidence per legal hold, (c) file a CyberTipline report to
   NCMEC (US operators), (d) ban the account/device.
4. **Audit trail** for every match decision.

## Providers (require external accounts / approval — the blocker)

| Provider | Covers | Access | Cost |
|----------|--------|--------|------|
| **Microsoft PhotoDNA** (Azure / Cloud Service) | CSAM image hashing | Application + vetting by Microsoft; not instant | Free for qualifying platforms |
| **Google Content Safety API / CSAI Match** | CSAM image + video | Application + vetting by Google | Free for qualifying platforms |
| **NCMEC hash sharing** | Known CSAM hashes | US ESP registration (18 U.S.C. §2258A) | Free |
| **StopNCII.org** | NCII (adult intimate images) | Partner integration request | Free |
| **Thorn Safer** | CSAM image+video, turnkey | Commercial contract | Paid |

**Recommended path:** PhotoDNA (images) + Google CSAI (video) + StopNCII (NCII),
plus NCMEC registration for the reporting obligation. All except Thorn are free but
gated behind an application/vetting step that takes days–weeks — start early.

## Where it plugs into this codebase

The upload pipeline already has the right seam:

- `backend/crates/api/src/media.rs` → `create_photo` downloads the original from R2,
  generates a blur rendition, then inserts the `photos` row. **The hash-match call
  goes here, between download and insert** — reject (and never insert) on a positive
  match. The same seam covers album photos and story media that route through
  `create_photo`.
- `nsfw/` already does on-device NSFW gating; CSAM/NCII is a *separate, server-side,
  non-optional* check — do not conflate them (NSFW is consensual-adult content;
  CSAM/NCII is illegal content and must be server-authoritative).

## Suggested implementation shape (when accounts exist)

1. New crate/module `backend/crates/api/src/safety_hash.rs` with a
   `trait SafetyScanner { async fn scan(&self, bytes: &[u8]) -> ScanVerdict }` and
   one impl per provider; a `NoopScanner` for dev.
2. Config via env (`PHOTODNA_API_KEY`, etc.), scanner selected at boot.
3. In `create_photo`: `match scanner.scan(&image_bytes).await { Match => reject + report + ban; Clear => continue }`.
4. Reporting worker (queue) for NCMEC CyberTipline submission + evidence hold.
5. Integration tests with provider sandbox / known test hashes.

## Interim posture (pre-launch, no provider yet)

- Manual moderation queue (reports + verification already exist) is the stopgap.
- **Do not open public/unauthenticated signup at scale** until automated scanning is
  live — manual review does not satisfy the legal obligation for a live dating app.
