-- Ustara: add an optional Telegram profile field captured at signup
--
-- Legal first/last name stay concatenated into the existing full_name
-- column (no schema change, no blast radius across the app) — only the
-- signup form splits them into two inputs. Telegram is a genuinely new,
-- separate piece of self-reported data (distinct from telegram_chat_id,
-- which is the verified id from the bot-linking flow in
-- sql/15-telegram-bot.sql), so it gets its own column.

alter table barbers add column if not exists telegram_username text;
alter table clients add column if not exists telegram_username text;

create or replace function handle_new_user()
returns trigger as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if meta ->> 'role' = 'barber' then
    insert into public.barbers (id, full_name, phone, telegram_username, district, bio, years_experience, specialties)
    values (
      new.id,
      coalesce(meta ->> 'full_name', ''),
      coalesce(meta ->> 'phone', ''),
      nullif(meta ->> 'telegram_username', ''),
      meta ->> 'district',
      meta ->> 'bio',
      nullif(meta ->> 'years_experience', '')::int,
      case when meta ? 'specialties'
        then array(select jsonb_array_elements_text(meta -> 'specialties'))
        else '{}'::text[]
      end
    )
    on conflict (id) do nothing;
  elsif meta ->> 'role' = 'client' then
    insert into public.clients (id, full_name, phone, telegram_username)
    values (
      new.id,
      coalesce(meta ->> 'full_name', ''),
      meta ->> 'phone',
      nullif(meta ->> 'telegram_username', '')
    )
    on conflict (id) do nothing;
  end if;
  return new;
exception when others then
  -- never let a profile-creation hiccup break account creation itself
  return new;
end;
$$ language plpgsql security definer set search_path = public;
