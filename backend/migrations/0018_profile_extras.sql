-- Add columns to profiles table for the Profile feature (F1.6)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS birthdate date;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS ethnicity text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS profile_photo_id uuid REFERENCES photos(id) ON DELETE SET NULL;
