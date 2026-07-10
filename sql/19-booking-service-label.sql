-- Ustara: snapshot the service display name onto each booking
--
-- Bookings only stored service_key. For the 6 fixed services that key maps
-- to a translated name at render time, but for barber-defined custom
-- services (sql/16) the key is 'custom_<uuid>' — so booking rows, the
-- upcoming-appointment card, reminders, and analytics would all show the
-- raw key. Snapshotting the label at booking time follows the pattern this
-- table already uses for client_name / service_price / duration, and keeps
-- history correct even if the barber renames or deletes the service later.

alter table bookings add column if not exists service_label text;
