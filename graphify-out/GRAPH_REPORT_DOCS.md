# Graph Report - docs/ + updates  (2026-07-06)

## Corpus Check
- 25 files · ~60,000 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 38 nodes · 48 edges · 11 communities (6 shown, 5 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.87)
- Token cost: 237,000 input · 5,000 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Master Design & Architecture|Master Design & Architecture]]
- [[_COMMUNITY_Frontend Specs & UI Parity|Frontend Specs & UI Parity]]
- [[_COMMUNITY_Infrastructure & Deploy|Infrastructure & Deploy]]
- [[_COMMUNITY_Reality Updates (2026-07-06)|Reality Updates (2026-07-06)]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]

## God Nodes (most connected - your core abstractions)
1. `Grindr Clone Master Design Spec` - 14 edges
2. `Flutter FRB Frontend Design Spec` - 9 edges
3. `F0.6 Deploy Infra Design Spec` - 5 edges
4. `Rust+Axum Backend (api, db, auth, billing)` - 5 edges
5. `Grindr UI Parity Design Spec` - 4 edges
6. `Grindr 100% Functional+Visual Parity` - 4 edges
7. `F0.1 Monorepo Backend Scaffold Plan` - 3 edges
8. `F0.2 Database Schema Design Spec` - 3 edges
9. `F0.3 Auth System Design Spec` - 3 edges
10. `Admin Panel Design Spec` - 3 edges

## Surprising Connections (you probably didn't know these)
- `F0.4 RN App Shell Design Spec` --references--> `Grindr Clone Master Design Spec`  [EXTRACTED]
  docs/superpowers/specs/2026-06-26-f0.4-rn-app-shell-design.md → docs/superpowers/specs/2026-06-25-grindr-clone-design.md
- `F0.5 Next.js Marketing Design Spec` --references--> `Grindr Clone Master Design Spec`  [EXTRACTED]
  docs/superpowers/specs/2026-06-26-f0.5-nextjs-marketing-design.md → docs/superpowers/specs/2026-06-25-grindr-clone-design.md
- `Neon PostgreSQL 16 + PostGIS` --conceptually_related_to--> `Rust+Axum Backend (api, db, auth, billing)`  [INFERRED]
  docs/superpowers/specs/2026-06-26-f0.6-deploy-infra-design.md → docs/superpowers/specs/2026-06-25-grindr-clone-design.md
- `Cloudflare R2 Media Storage` --conceptually_related_to--> `Rust+Axum Backend (api, db, auth, billing)`  [INFERRED]
  docs/superpowers/specs/2026-06-26-f0.6-deploy-infra-design.md → docs/superpowers/specs/2026-06-25-grindr-clone-design.md
- `F0.1 Monorepo Backend Scaffold Plan` --references--> `Grindr Clone Master Design Spec`  [EXTRACTED]
  docs/superpowers/plans/2026-06-25-f0.1-monorepo-backend-scaffold.md → docs/superpowers/specs/2026-06-25-grindr-clone-design.md

## Hyperedges (group relationships)
- **Rust Backend Stack** — rust_axum_backend, core_crate, f01_plan, f02_spec, f03_spec, neon_postgresql, redis_infra [INFERRED 0.85]
- **Flutter Frontend Stack** — flutter_spec, flutter_plan, thin_waist_arch, core_crate, frb_v2, nsfw_client_side, messagepack_proto, vibra_theme_v3 [INFERRED 0.85]
- **Deploy Infrastructure Platform** — f06_spec, f06_plan, neon_postgresql, cloudflare_r2, redis_infra, aws_ec2_vps [INFERRED 0.85]

## Communities (11 total, 5 thin omitted)

### Community 0 - "Master Design & Architecture"
Cohesion: 0.38
Nodes (7): Grindr 100% Parity Implementation Plan, Grindr 100% Parity Design Spec, Grindr 100% Functional+Visual Parity, Grindr UI Parity Plan, Grindr UI Parity Design Spec, Grindr Parity Audit 2026-07-05, VibraTheme v3 Design Tokens

### Community 1 - "Frontend Specs & UI Parity"
Cohesion: 0.4
Nodes (6): AWS EC2 Graviton VPS (t4g.small), Cloudflare R2 Media Storage, F0.6 Deploy Infra Plan, F0.6 Deploy Infra Design Spec, Neon PostgreSQL 16 + PostGIS, Rust+Axum Backend (api, db, auth, billing)

### Community 2 - "Infrastructure & Deploy"
Cohesion: 0.4
Nodes (5): Flutter FRB Frontend Implementation Plan, Flutter FRB Frontend Design Spec, flutter_rust_bridge v2, Full Functional Final Plan (chat media + NSFW), MessagePack Protocol with JSON Fallback

### Community 3 - "Reality Updates (2026-07-06)"
Cohesion: 0.5
Nodes (4): Grindr Clone Master Design Spec, proyecto-X Project, Redis for presence, pub/sub, geo, rate-limit, RevenueCat IAP Integration

### Community 4 - "Community 4"
Cohesion: 0.67
Nodes (3): Admin RBAC + Immutable Audit Log + TOTP 2FA, Admin Panel Design Spec, Server-Authoritative Feature Gating

### Community 5 - "Community 5"
Cohesion: 0.67
Nodes (3): F0.1 Monorepo Backend Scaffold Plan, F0.2 Complete Schema Plan, F0.2 Database Schema Design Spec

## Knowledge Gaps
- **14 isolated node(s):** `F0.3 Auth Implementation Plan`, `F0.4 RN App Shell Plan`, `F0.5 Next.js Marketing Plan`, `F0.6 Deploy Infra Plan`, `Flutter FRB Frontend Implementation Plan` (+9 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Grindr Clone Master Design Spec` connect `Reality Updates (2026-07-06)` to `Master Design & Architecture`, `Frontend Specs & UI Parity`, `Infrastructure & Deploy`, `Community 4`, `Community 5`, `Community 8`, `Community 9`, `Community 10`?**
  _High betweenness centrality (0.828) - this node is a cross-community bridge._
- **Why does `Flutter FRB Frontend Design Spec` connect `Infrastructure & Deploy` to `Reality Updates (2026-07-06)`, `Community 4`, `Community 6`, `Community 7`?**
  _High betweenness centrality (0.426) - this node is a cross-community bridge._
- **Why does `F0.6 Deploy Infra Design Spec` connect `Frontend Specs & UI Parity` to `Reality Updates (2026-07-06)`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Rust+Axum Backend (api, db, auth, billing)` (e.g. with `Neon PostgreSQL 16 + PostGIS` and `Redis for presence, pub/sub, geo, rate-limit`) actually correct?**
  _`Rust+Axum Backend (api, db, auth, billing)` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `F0.3 Auth Implementation Plan`, `F0.4 RN App Shell Plan`, `F0.5 Next.js Marketing Plan` to the rest of the system?**
  _14 weakly-connected nodes found - possible documentation gaps or missing edges._