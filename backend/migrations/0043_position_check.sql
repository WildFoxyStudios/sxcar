-- The app's position picker offers Top, Bottom, Versatile, Side, Oral, Other,
-- but the original CHECK only allowed a lowercase legacy set
-- ('top','vers_top','versatile','vers_bottom','bottom','side'), so saving a
-- position from onboarding or edit-profile failed with a 500. The backend now
-- normalizes position to lowercase; expand the constraint to match the app's
-- option set (keeping the legacy vers_top/vers_bottom values for compatibility).
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_position_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_position_check
  CHECK (position IN ('top','bottom','versatile','side','oral','other','vers_top','vers_bottom'));
