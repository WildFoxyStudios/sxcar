-- Índices adicionales (revisión final F0.2): consultas simétricas.
-- "Taps que envié" y "perfiles que vi" (los inversos de los índices ya existentes).
CREATE INDEX idx_taps_from ON taps(from_user, created_at);
CREATE INDEX idx_profile_views_viewer ON profile_views(viewer_id, viewed_at);
