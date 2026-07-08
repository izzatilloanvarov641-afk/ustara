-- Ustara: let barbers add their own custom services beyond the fixed 6
-- (haircut, beard_trim, haircut_beard, kids_haircut, lineup, coloring).
-- Custom rows use a client-generated service_key like 'custom_<uuid>' and
-- carry their own display name in custom_label; fixed rows keep
-- custom_label null and are still named via the shared SERVICES_LOCAL map.

alter table services drop constraint if exists services_service_key_check;

alter table services add constraint services_service_key_check
  check (
    service_key in ('haircut','beard_trim','haircut_beard','kids_haircut','lineup','coloring')
    or service_key like 'custom_%'
  );

alter table services add column if not exists custom_label text;
