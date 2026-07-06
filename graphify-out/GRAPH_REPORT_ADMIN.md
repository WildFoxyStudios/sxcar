# Graph Report - apps/admin/lib  (2026-07-06)

## Corpus Check
- Corpus is ~19,440 words - fits in a single context window. You may not need a graph.

## Summary
- 482 nodes · 603 edges · 22 communities (21 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
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

## God Nodes (most connected - your core abstractions)
1. `package:flutter_riverpod/flutter_riverpod.dart` - 25 edges
2. `package:flutter/material.dart` - 24 edges
3. `../theme/admin_theme.dart` - 22 edges
4. `../../widgets/admin_http_client.dart` - 21 edges
5. `../../widgets/admin_layout.dart` - 19 edges
6. `package:dio/dio.dart` - 15 edges
7. `package:go_router/go_router.dart` - 5 edges
8. `../auth/admin_auth_provider.dart` - 3 edges
9. `AdminApp` - 1 edges
10. `main` - 1 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Communities (22 total, 1 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (41): ../auth/admin_auth_provider.dart, AdminApp, build, _createRouter, GoRouter, main, ProviderScope, build (+33 more)

### Community 1 - "Community 1"
Cohesion: 0.08
Nodes (25): _ActionBtn, AdminLayout, Align, _body, build, Center, _Chip, CmsContent (+17 more)

### Community 2 - "Community 2"
Cohesion: 0.08
Nodes (24): AdminLayout, Align, _body, build, Center, _Chip, _ColHeader, Column (+16 more)

### Community 3 - "Community 3"
Cohesion: 0.08
Nodes (24): _ActionBtn, AdminLayout, Align, ApiKey, _ApiKeyRow, ApiKeysScreen, _body, build (+16 more)

### Community 4 - "Community 4"
Cohesion: 0.08
Nodes (23): _ActionBtn, AdminLayout, build, Center, Column, Container, _dialogInfo, Divider (+15 more)

### Community 5 - "Community 5"
Cohesion: 0.08
Nodes (23): AdminLayout, Align, build, _buildTable, Center, _ColHeader, Column, Container (+15 more)

### Community 6 - "Community 6"
Cohesion: 0.09
Nodes (22): _ActionBtn, AdminLayout, Align, _body, build, Center, _Chip, _ColHeader (+14 more)

### Community 7 - "Community 7"
Cohesion: 0.09
Nodes (22): _ActionBtn, AdminLayout, Align, _body, build, Center, _ColHeader, Column (+14 more)

### Community 8 - "Community 8"
Cohesion: 0.09
Nodes (22): _ActionBtn, AdminLayout, Align, _body, build, Center, _Chip, _ColHeader (+14 more)

### Community 9 - "Community 9"
Cohesion: 0.09
Nodes (22): _ActionBtn, AdminLayout, Align, _body, build, Center, _Chip, _ColHeader (+14 more)

### Community 10 - "Community 10"
Cohesion: 0.09
Nodes (21): AdminLayout, Align, _body, build, Center, _Chip, _ColHeader, Column (+13 more)

### Community 11 - "Community 11"
Cohesion: 0.09
Nodes (21): AdminLayout, Align, AuditEntry, _AuditRow, AuditScreen, _body, build, Center (+13 more)

### Community 12 - "Community 12"
Cohesion: 0.09
Nodes (21): _ActionBtn, AdminLayout, Align, _body, build, Center, _ColHeader, Column (+13 more)

### Community 13 - "Community 13"
Cohesion: 0.09
Nodes (21): AdminLayout, Align, _body, build, Campaign, _CampaignRow, CampaignsScreen, Center (+13 more)

### Community 14 - "Community 14"
Cohesion: 0.09
Nodes (21): AdminLayout, Align, _body, build, Center, _Chip, _ColHeader, Column (+13 more)

### Community 15 - "Community 15"
Cohesion: 0.1
Nodes (20): _ActionButton, AdminLayout, BackButton, build, _buildProfile, Center, Container, Divider (+12 more)

### Community 16 - "Community 16"
Cohesion: 0.11
Nodes (17): AdminAuthService, AbuseRule, AbuseRulesScreen, AdminLayout, _body, build, Center, _Chip (+9 more)

### Community 17 - "Community 17"
Cohesion: 0.11
Nodes (17): _AddFeatureButton, AdminLayout, build, Center, Column, Container, Divider, Icon (+9 more)

### Community 18 - "Community 18"
Cohesion: 0.12
Nodes (15): admin_auth_service.dart, AdminAuthService, AuthNotifier, AuthState, build, clearError, copyWith, _extractErrorMessage (+7 more)

### Community 19 - "Community 19"
Cohesion: 0.12
Nodes (16): AdminLayout, AnalyticsOverview, build, Container, DashboardScreen, _ErrorBanner, Expanded, _formatNumber (+8 more)

### Community 20 - "Community 20"
Cohesion: 0.12
Nodes (15): AdminLayout, build, Center, Column, Container, Divider, FeatureFlag, _FlagCard (+7 more)

## Knowledge Gaps
- **446 isolated node(s):** `AdminApp`, `main`, `ProviderScope`, `build`, `_createRouter` (+441 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.