# Migration Gap Notes

## Missing: 0027, 0028
Migrations 0027 and 0028 are absent between 0026_ephemeral_photos.sql (Sept 2023)
and 0029_subscriptions.sql (Jan 2024). These gaps are intentional — the numbered
sequence was preserved to avoid renaming downstream dependencies after the
migrations were removed or consolidated during development.
