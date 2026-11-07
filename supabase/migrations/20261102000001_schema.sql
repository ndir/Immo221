-- =====================================================================
-- Dëkk — schéma principal
-- Demandes immobilières par note vocale, mise en relation via WhatsApp.
-- Cible : Supabase (Postgres 15+). Montants en FCFA entiers (XOF).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
create type public.user_role as enum ('seeker', 'owner', 'broker', 'agency', 'admin');
create type public.transaction_type as enum ('location', 'colocation', 'achat', 'terrain');
create type public.property_type as enum (
  'chambre', 'studio', 'appartement', 'maison', 'villa', 'terrain', 'local_commercial', 'autre'
);
create type public.request_status as enum (
  'uploaded', 'processing', 'draft', 'published', 'found', 'expired', 'failed', 'removed'
);
create type public.request_source as enum ('app', 'web', 'whatsapp');

-- ---------------------------------------------------------------------
-- Réglages globaux (une seule ligne)
-- free_mode = true : lancement gratuit, contacts illimités pour les offreurs.
-- Passer à false le jour où les forfaits sont activés.
-- ---------------------------------------------------------------------
create table public.app_settings (
  id boolean primary key default true check (id),
  free_mode boolean not null default true,
  max_contacts_default int not null default 5,
  owner_daily_unlock_limit int not null default 30,
  push_daily_limit int not null default 10,
  request_reports_to_suspend int not null default 3
);
insert into public.app_settings default values;

-- ---------------------------------------------------------------------
-- Profils (1-1 avec auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.user_role not null default 'seeker',
  display_name text not null default '',
  phone text unique,                       -- E.164 : +221XXXXXXXXX
  whatsapp_phone text,
  agency_name text,
  ninea text,
  is_verified boolean not null default false,
  is_suspended boolean not null default false,
  rating_avg numeric(2, 1) not null default 0,
  rating_count int not null default 0,
  preferred_lang text not null default 'fr' check (preferred_lang in ('fr', 'wo')),
  fcm_token text,
  created_at timestamptz not null default now()
);

create table public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  instant_alerts boolean not null default true,     -- offreur : sinon résumé matin et soir
  quiet_hours boolean not null default true,        -- silence 22 h – 7 h (heure de Dakar = UTC)
  daily_listen_digest boolean not null default false
);

-- Préférences par type de notification (absence de ligne = activé)
create table public.notification_prefs (
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  enabled boolean not null default true,
  primary key (user_id, type)
);

-- ---------------------------------------------------------------------
-- Référentiel des zones (quartiers et villes du Sénégal)
-- ---------------------------------------------------------------------
create table public.zones (
  id serial primary key,
  name text not null,
  city text not null,
  region text not null,
  aliases text[] not null default '{}',
  unique (name, city)
);

-- ---------------------------------------------------------------------
-- Demandes vocales
-- ---------------------------------------------------------------------
create table public.requests (
  id uuid primary key default gen_random_uuid(),
  seeker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  source public.request_source not null default 'app',
  status public.request_status not null default 'uploaded',
  audio_path text not null,
  audio_duration_s int check (audio_duration_s between 1 and 180),
  transcript text,
  transcript_lang text,
  ai_raw jsonb,
  ai_confidence numeric(3, 2),
  ai_error text,
  transaction public.transaction_type,
  property public.property_type,
  zone_ids int[] not null default '{}',
  zone_free_text text,
  budget_min int check (budget_min is null or budget_min >= 0),
  budget_max int check (budget_max is null or budget_max >= 0),
  budget_period text check (budget_period is null or budget_period in ('mois', 'total')),
  bedrooms_min int check (bedrooms_min is null or bedrooms_min between 0 and 20),
  furnished boolean,
  move_in text,
  is_urgent boolean not null default false,
  summary text,
  user_edited boolean not null default false,
  max_contacts int not null default 5,
  contacts_count int not null default 0,
  listen_count int not null default 0,
  expires_at timestamptz,
  reminded_at timestamptz,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  closed_at timestamptz
);
create index requests_feed_idx on public.requests (status, expires_at desc);
create index requests_zone_idx on public.requests using gin (zone_ids);
create index requests_seeker_idx on public.requests (seeker_id, created_at desc);

-- Abonnements des offreurs : zones et critères suivis (null = tous)
create table public.owner_subscriptions (
  id bigserial primary key,
  owner_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  zone_id int not null references public.zones (id) on delete cascade,
  transaction public.transaction_type,
  property public.property_type,
  unique nulls not distinct (owner_id, zone_id, transaction, property)
);
create index owner_subscriptions_zone_idx on public.owner_subscriptions (zone_id);

-- Déblocages de contact (le point de facturation futur)
create table public.unlocks (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  credits_spent int not null default 0,
  outcome text not null default 'en_cours' check (outcome in ('en_cours', 'conclu', 'sans_suite')),
  created_at timestamptz not null default now(),
  unique (request_id, owner_id)
);
create index unlocks_owner_idx on public.unlocks (owner_id, created_at desc);

-- Écoutes du vocal (une par offreur et par demande)
create table public.request_listens (
  request_id uuid not null references public.requests (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (request_id, owner_id)
);

-- Avis laissé par le demandeur à la clôture
create table public.reviews (
  request_id uuid primary key references public.requests (id) on delete cascade,
  seeker_id uuid not null references public.profiles (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

-- Signalements
create table public.reports (
  id bigserial primary key,
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  target_owner_id uuid not null references public.profiles (id) on delete cascade,
  request_id uuid references public.requests (id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  unique (reporter_id, target_owner_id)
);

-- Notifications (centre in-app + file d'envoi push)
create table public.notifications (
  id bigserial primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  priority text not null default 'normal' check (priority in ('normal', 'high')),
  read_at timestamptz,
  push_status text not null default 'pending'
    check (push_status in ('pending', 'sent', 'deferred', 'skipped', 'failed')),
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_deferred_idx on public.notifications (push_status) where push_status = 'deferred';

-- Forfaits (préparés pour l'après-lancement ; inutilisés tant que free_mode = true)
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  plan text not null check (plan in ('particulier', 'pro', 'agence')),
  contacts_left int,                       -- null = illimité
  valid_until timestamptz not null,
  created_at timestamptz not null default now()
);
create index subscriptions_owner_idx on public.subscriptions (owner_id, valid_until desc);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  provider text not null check (provider in ('wave', 'orange_money')),
  provider_ref text,
  plan text not null,
  amount_xof int not null check (amount_xof > 0),
  status text not null default 'initiated' check (status in ('initiated', 'pending', 'success', 'failed', 'refunded')),
  raw_webhook jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_ref)
);

-- =====================================================================
-- Fonctions utilitaires
-- =====================================================================

create or replace function public.normalize_phone(p text)
returns text language sql immutable as $$
  select case
    when p is null or btrim(p) = '' then null
    when regexp_replace(p, '[^0-9+]', '', 'g') like '+%' then regexp_replace(p, '[^0-9+]', '', 'g')
    when length(regexp_replace(p, '[^0-9]', '', 'g')) = 9 then '+221' || regexp_replace(p, '[^0-9]', '', 'g')
    else '+' || regexp_replace(p, '[^0-9]', '', 'g')
  end
$$;

create or replace function public.is_offerer(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role in ('owner', 'broker', 'agency', 'admin') and not is_suspended
  )
$$;

create or replace function public.first_name(full_name text)
returns text language sql immutable as $$
  select nullif(split_part(btrim(coalesce(full_name, '')), ' ', 1), '')
$$;

-- Crée une notification si le destinataire n'a pas désactivé ce type.
create or replace function public.notify_user(
  p_user uuid, p_type text, p_title text, p_body text,
  p_data jsonb default '{}', p_priority text default 'normal'
) returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.notification_prefs
    where user_id = p_user and type = p_type and not enabled
  ) then
    return;
  end if;
  insert into public.notifications (user_id, type, title, body, data, priority)
  values (p_user, p_type, p_title, p_body, coalesce(p_data, '{}'), p_priority);
end $$;

create or replace function public.format_fcfa(amount int)
returns text language sql immutable as $$
  select case when amount is null then null
    when amount >= 1000000 and amount % 100000 = 0
      then trim(trailing ',' from trim(trailing '0' from replace(to_char(amount / 1000000.0, 'FM999990.0'), '.', ','))) || ' M FCFA'
    else replace(to_char(amount, 'FM999G999G999'), ',', ' ') || ' F'
  end
$$;

-- =====================================================================
-- Profils : création automatique et protections
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_phone text := public.normalize_phone(new.phone);
begin
  insert into public.profiles (id, phone, whatsapp_phone, display_name)
  values (
    new.id, v_phone, v_phone,
    coalesce(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  insert into public.user_settings (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Change le rôle de l'utilisateur courant (jamais admin).
create or replace function public.set_my_role(p_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_role = 'admin' then raise exception 'forbidden_role'; end if;
  update public.profiles set role = p_role where id = auth.uid() and role <> 'admin';
end $$;

-- =====================================================================
-- Demandes : publication et cycle de vie
-- =====================================================================

create or replace function public.zone_label(p_zone_ids int[], p_free text)
returns text language sql stable set search_path = public as $$
  select coalesce(
    (select string_agg(z.name, ', ' order by array_position(p_zone_ids, z.id))
       from public.zones z where z.id = any (p_zone_ids)),
    nullif(p_free, ''),
    'zone non précisée'
  )
$$;

create or replace function public.request_title(r public.requests)
returns text language sql stable set search_path = public as $$
  select initcap(coalesce(r.transaction::text, 'recherche')) || ' · '
    || coalesce(replace(r.property::text, '_', ' '), 'bien') || ' · '
    || public.zone_label(r.zone_ids, r.zone_free_text)
$$;

create or replace function public.publish_request(
  p_request_id uuid,
  p_transaction public.transaction_type,
  p_property public.property_type,
  p_zone_ids int[],
  p_zone_free_text text,
  p_budget_min int,
  p_budget_max int,
  p_budget_period text,
  p_bedrooms_min int,
  p_furnished boolean,
  p_move_in text,
  p_summary text,
  p_visibility_days int default 15,
  p_is_urgent boolean default false,
  p_user_edited boolean default false
) returns public.requests
language plpgsql security definer set search_path = public as $$
declare
  r public.requests;
  was_published boolean;
  settings public.app_settings;
  v_budget text;
begin
  select * into r from public.requests where id = p_request_id for update;
  if not found or r.seeker_id is distinct from auth.uid() then
    raise exception 'request_not_found';
  end if;
  if r.status not in ('draft', 'published', 'failed') then
    raise exception 'request_not_publishable';
  end if;
  if p_visibility_days not in (7, 15, 30) then
    raise exception 'invalid_visibility';
  end if;
  if p_transaction is null then
    raise exception 'transaction_required';
  end if;
  if coalesce(array_length(p_zone_ids, 1), 0) = 0 and coalesce(btrim(p_zone_free_text), '') = '' then
    raise exception 'zone_required';
  end if;
  if p_budget_min is not null and p_budget_max is not null and p_budget_min > p_budget_max then
    raise exception 'invalid_budget';
  end if;

  select * into settings from public.app_settings;
  was_published := r.status = 'published';

  update public.requests set
    transaction = p_transaction,
    property = p_property,
    zone_ids = coalesce(p_zone_ids, '{}'),
    zone_free_text = nullif(btrim(p_zone_free_text), ''),
    budget_min = p_budget_min,
    budget_max = p_budget_max,
    budget_period = p_budget_period,
    bedrooms_min = p_bedrooms_min,
    furnished = p_furnished,
    move_in = nullif(btrim(p_move_in), ''),
    summary = nullif(btrim(p_summary), ''),
    is_urgent = coalesce(p_is_urgent, false),
    user_edited = r.user_edited or coalesce(p_user_edited, false),
    status = 'published',
    max_contacts = coalesce(r.max_contacts, settings.max_contacts_default),
    published_at = coalesce(r.published_at, now()),
    expires_at = case when was_published then r.expires_at
                      else now() + make_interval(days => p_visibility_days) end
  where id = p_request_id
  returning * into r;

  if not was_published then
    perform public.notify_user(
      r.seeker_id, 'request_published', 'Votre demande est en ligne',
      'Les offreurs de ' || public.zone_label(r.zone_ids, r.zone_free_text) || ' ont été prévenus.',
      jsonb_build_object('request_id', r.id)
    );

    v_budget := case when r.budget_max is not null
      then 'Max ' || public.format_fcfa(r.budget_max) || case when r.budget_period = 'mois' then ' / mois' else '' end
      else 'Budget non précisé' end;

    -- Alerte les offreurs abonnés aux zones et critères de la demande
    perform public.notify_user(
      s.owner_id,
      'new_request',
      case when r.is_urgent then 'Urgent · ' else '' end || public.request_title(r),
      coalesce(r.summary, v_budget),
      jsonb_build_object('request_id', r.id),
      case when r.is_urgent then 'high' else 'normal' end
    )
    from (
      select distinct os.owner_id
      from public.owner_subscriptions os
      join public.profiles p on p.id = os.owner_id
      where os.zone_id = any (r.zone_ids)
        and (os.transaction is null or os.transaction = r.transaction)
        and (os.property is null or os.property = r.property)
        and os.owner_id <> r.seeker_id
        and p.role in ('owner', 'broker', 'agency', 'admin')
        and not p.is_suspended
    ) s;
  end if;

  return r;
end $$;

create or replace function public.extend_request(p_request_id uuid, p_days int default 15)
returns public.requests language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  if p_days not in (7, 15, 30) then raise exception 'invalid_visibility'; end if;
  update public.requests
     set expires_at = greatest(coalesce(expires_at, now()), now()) + make_interval(days => p_days),
         status = 'published', reminded_at = null
   where id = p_request_id and seeker_id = auth.uid() and status in ('published', 'expired')
  returning * into r;
  if not found then raise exception 'request_not_found'; end if;
  return r;
end $$;

create or replace function public.remove_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.requests set status = 'removed', closed_at = now()
   where id = p_request_id and seeker_id = auth.uid() and status not in ('found', 'removed');
  if not found then raise exception 'request_not_found'; end if;
end $$;

-- Le demandeur a trouvé : clôture, avis facultatif sur l'offreur qui l'a aidé.
create or replace function public.close_request(
  p_request_id uuid, p_helped_owner uuid default null, p_rating int default null
) returns void language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_request_id and seeker_id = auth.uid() for update;
  if not found then raise exception 'request_not_found'; end if;
  if r.status in ('found', 'removed') then return; end if;

  update public.requests set status = 'found', closed_at = now() where id = p_request_id;

  if p_helped_owner is not null then
    if not exists (select 1 from public.unlocks where request_id = p_request_id and owner_id = p_helped_owner) then
      raise exception 'owner_not_in_contacts';
    end if;
    update public.unlocks set outcome = 'conclu' where request_id = p_request_id and owner_id = p_helped_owner;

    if p_rating between 1 and 5 then
      insert into public.reviews (request_id, seeker_id, owner_id, rating)
      values (p_request_id, r.seeker_id, p_helped_owner, p_rating)
      on conflict (request_id) do nothing;
      update public.profiles p set
        rating_count = s.cnt,
        rating_avg = round(s.avg_rating, 1)
      from (select count(*) cnt, avg(rating) avg_rating from public.reviews where owner_id = p_helped_owner) s
      where p.id = p_helped_owner;
    end if;

    perform public.notify_user(
      p_helped_owner, 'found_thanks',
      coalesce(public.first_name((select display_name from public.profiles where id = r.seeker_id)), 'Un demandeur')
        || ' a trouvé grâce à vous',
      case when p_rating between 1 and 5 then 'Note reçue : ' || p_rating || '/5. Merci !'
           else 'Merci pour votre aide.' end,
      jsonb_build_object('request_id', p_request_id)
    );
  end if;
end $$;

-- =====================================================================
-- Offreurs : écoute, déblocage du contact, suivi
-- =====================================================================

create or replace function public.register_listen(p_request_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_offerer(auth.uid()) then raise exception 'not_offerer'; end if;
  insert into public.request_listens (request_id, owner_id)
  select id, auth.uid() from public.requests where id = p_request_id and status = 'published'
  on conflict do nothing;
  if found then
    update public.requests set listen_count = listen_count + 1 where id = p_request_id;
  end if;
end $$;

-- Débloque le numéro WhatsApp du demandeur et prépare le message.
-- Retour : { whatsapp_phone, seeker_name, message, already_unlocked }
create or replace function public.unlock_contact(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r public.requests;
  seeker public.profiles;
  me public.profiles;
  settings public.app_settings;
  sub public.subscriptions;
  existing public.unlocks;
  v_msg text;
  v_today int;
begin
  select * into me from public.profiles where id = auth.uid();
  if not found or me.role not in ('owner', 'broker', 'agency', 'admin') then
    raise exception 'not_offerer';
  end if;
  if me.is_suspended then raise exception 'account_suspended'; end if;

  select * into r from public.requests where id = p_request_id for update;
  if not found then raise exception 'request_not_found'; end if;
  select * into seeker from public.profiles where id = r.seeker_id;

  select * into existing from public.unlocks where request_id = r.id and owner_id = me.id;
  if found then
    v_msg := null;
  else
    if r.status <> 'published' or r.expires_at <= now() then raise exception 'request_closed'; end if;
    if r.seeker_id = me.id then raise exception 'own_request'; end if;
    if r.contacts_count >= r.max_contacts then raise exception 'contacts_full'; end if;

    select * into settings from public.app_settings;
    select count(*) into v_today from public.unlocks
     where owner_id = me.id and created_at > now() - interval '1 day';
    if v_today >= settings.owner_daily_unlock_limit then raise exception 'daily_limit_reached'; end if;

    if not settings.free_mode then
      select * into sub from public.subscriptions
       where owner_id = me.id and valid_until > now() and (contacts_left is null or contacts_left > 0)
       order by valid_until desc limit 1 for update;
      if not found then raise exception 'subscription_required'; end if;
      if sub.contacts_left is not null then
        update public.subscriptions set contacts_left = contacts_left - 1 where id = sub.id;
      end if;
    end if;

    insert into public.unlocks (request_id, owner_id, credits_spent)
    values (r.id, me.id, case when settings.free_mode then 0 else 1 end);
    update public.requests set contacts_count = contacts_count + 1 where id = r.id;

    perform public.notify_user(
      r.seeker_id, 'owner_contacted',
      coalesce(nullif(me.agency_name, ''), nullif(me.display_name, ''), 'Un offreur') || ' vous a écrit sur WhatsApp',
      case me.role when 'agency' then 'Agence' when 'broker' then 'Démarcheur' else 'Propriétaire' end
        || case when me.is_verified then ' vérifié(e)' else '' end
        || case when me.rating_count > 0 then ' · ' || replace(me.rating_avg::text, '.', ',') || ' ★' else '' end,
      jsonb_build_object('request_id', r.id, 'owner_id', me.id),
      'high'
    );
  end if;

  v_msg := 'Bonjour' || coalesce(' ' || public.first_name(seeker.display_name), '')
    || ', je vous contacte via Dëkk pour votre recherche : '
    || coalesce(r.summary, public.request_title(r)) || '. J''ai un bien à vous proposer.';

  return jsonb_build_object(
    'whatsapp_phone', seeker.whatsapp_phone,
    'seeker_name', public.first_name(seeker.display_name),
    'message', v_msg,
    'already_unlocked', existing.id is not null
  );
end $$;

create or replace function public.set_unlock_outcome(p_request_id uuid, p_outcome text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.unlocks set outcome = p_outcome
   where request_id = p_request_id and owner_id = auth.uid();
  if not found then raise exception 'unlock_not_found'; end if;
end $$;

create or replace function public.report_owner(p_owner uuid, p_request_id uuid default null, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_count int; v_limit int;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_owner = auth.uid() then raise exception 'invalid_target'; end if;
  insert into public.reports (reporter_id, target_owner_id, request_id, reason)
  values (auth.uid(), p_owner, p_request_id, left(p_reason, 500))
  on conflict (reporter_id, target_owner_id) do nothing;

  select request_reports_to_suspend into v_limit from public.app_settings;
  select count(distinct reporter_id) into v_count from public.reports where target_owner_id = p_owner;
  if v_count >= v_limit then
    update public.profiles set is_suspended = true where id = p_owner and role <> 'admin';
  end if;
end $$;

create or replace function public.mark_notifications_read(p_ids bigint[] default null)
returns void language sql security definer set search_path = public as $$
  update public.notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids));
$$;

-- =====================================================================
-- Tâches planifiées (pg_cron) — voir docs/MISE_EN_LIGNE.md
-- =====================================================================

-- Passe en « expiré » les demandes dont la date de fin est dépassée.
create or replace function public.expire_requests()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.requests set status = 'expired'
   where status = 'published' and expires_at <= now();
  get diagnostics n = row_count;
  return n;
end $$;

-- Prévient le demandeur 2 jours avant l'expiration (une seule fois).
create or replace function public.remind_expiring()
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in
    select id, seeker_id, expires_at from public.requests
     where status = 'published' and reminded_at is null
       and expires_at > now() and expires_at <= now() + interval '2 days'
     for update skip locked
  loop
    perform public.notify_user(
      r.seeker_id, 'request_expiring',
      'Votre demande expire dans ' ||
        case when r.expires_at <= now() + interval '1 day' then 'moins d''un jour' else '2 jours' end,
      'Toujours en recherche ? Prolongez-la en un tap.',
      jsonb_build_object('request_id', r.id), 'high'
    );
    update public.requests set reminded_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Résumé quotidien des écoutes pour les demandeurs qui l'ont activé.
create or replace function public.daily_listen_digest()
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in
    select q.seeker_id, q.id, q.listen_count, count(l.*) as new_listens
      from public.requests q
      join public.user_settings s on s.user_id = q.seeker_id and s.daily_listen_digest
      join public.request_listens l on l.request_id = q.id and l.created_at > now() - interval '1 day'
     where q.status = 'published'
     group by q.seeker_id, q.id, q.listen_count
  loop
    perform public.notify_user(
      r.seeker_id, 'listen_digest',
      'Votre vocal a été écouté ' || r.new_listens || ' fois de plus',
      r.listen_count || ' écoutes au total.',
      jsonb_build_object('request_id', r.id)
    );
    n := n + 1;
  end loop;
  return n;
end $$;

-- =====================================================================
-- Vues
-- =====================================================================

-- Fil des demandes pour les offreurs (sans identifiant ni numéro du demandeur).
create or replace view public.feed as
select
  r.id, r.transaction, r.property, r.zone_ids,
  coalesce((select array_agg(z.name order by array_position(r.zone_ids, z.id))
              from public.zones z where z.id = any (r.zone_ids)), '{}') as zone_names,
  (select min(z.city) from public.zones z where z.id = any (r.zone_ids)) as city,
  r.zone_free_text, r.budget_min, r.budget_max, r.budget_period, r.bedrooms_min,
  r.furnished, r.move_in, r.is_urgent, r.summary, r.transcript,
  r.audio_path, r.audio_duration_s, r.contacts_count, r.max_contacts, r.listen_count,
  r.published_at, r.expires_at,
  public.first_name(p.display_name) as seeker_first_name,
  exists (select 1 from public.unlocks u where u.request_id = r.id and u.owner_id = auth.uid()) as already_unlocked
from public.requests r
join public.profiles p on p.id = r.seeker_id
where public.is_offerer(auth.uid())
  and r.status = 'published'
  and r.expires_at > now()
  and r.seeker_id <> auth.uid()
  and (r.contacts_count < r.max_contacts
       or exists (select 1 from public.unlocks u where u.request_id = r.id and u.owner_id = auth.uid()));

-- Pour le demandeur : qui l'a contacté, sur chacune de ses demandes.
create or replace view public.my_request_contacts as
select
  u.request_id, u.owner_id, u.created_at, u.outcome,
  coalesce(nullif(p.agency_name, ''), p.display_name) as owner_name,
  p.role as owner_role, p.is_verified, p.rating_avg, p.rating_count
from public.unlocks u
join public.requests r on r.id = u.request_id
join public.profiles p on p.id = u.owner_id
where r.seeker_id = auth.uid();

-- Pour l'offreur : les demandes qu'il a débloquées (« Mes contacts »).
create or replace view public.my_unlocks as
select
  u.request_id, u.created_at, u.outcome,
  r.status as request_status, r.summary, r.transaction, r.property, r.budget_max, r.budget_period,
  public.zone_label(r.zone_ids, r.zone_free_text) as zone_label,
  public.first_name(p.display_name) as seeker_first_name,
  p.whatsapp_phone as seeker_whatsapp
from public.unlocks u
join public.requests r on r.id = u.request_id
join public.profiles p on p.id = r.seeker_id
where u.owner_id = auth.uid();

-- =====================================================================
-- Sécurité : RLS et droits
-- =====================================================================

alter table public.app_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.zones enable row level security;
alter table public.requests enable row level security;
alter table public.owner_subscriptions enable row level security;
alter table public.unlocks enable row level security;
alter table public.request_listens enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon;

-- Réglages : lecture seule pour tous (affichage « gratuit au lancement »)
grant select on public.app_settings to anon, authenticated;
create policy app_settings_read on public.app_settings for select using (true);

-- Zones : publiques
grant select on public.zones to anon, authenticated;
create policy zones_read on public.zones for select using (true);

-- Profils : chacun lit et modifie sa propre ligne (colonnes non sensibles)
grant select on public.profiles to authenticated;
grant update (display_name, whatsapp_phone, agency_name, ninea, preferred_lang, fcm_token)
  on public.profiles to authenticated;
create policy profiles_self_read on public.profiles for select using (id = auth.uid());
create policy profiles_self_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

grant select, update (instant_alerts, quiet_hours, daily_listen_digest) on public.user_settings to authenticated;
create policy user_settings_self on public.user_settings for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.notification_prefs to authenticated;
create policy notification_prefs_self on public.notification_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Demandes : le demandeur lit ses demandes et en crée (statut initial uniquement).
-- Toute modification passe par les fonctions ci-dessus ou par le serveur.
grant select, insert on public.requests to authenticated;
create policy requests_seeker_read on public.requests for select using (seeker_id = auth.uid());
create policy requests_seeker_insert on public.requests for insert
  with check (
    seeker_id = auth.uid()
    and status = 'uploaded'
    and audio_path like auth.uid()::text || '/%'
  );

grant select, insert, delete on public.owner_subscriptions to authenticated;
grant usage on sequence public.owner_subscriptions_id_seq to authenticated;
create policy owner_subscriptions_self on public.owner_subscriptions for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid() and public.is_offerer(auth.uid()));

grant select on public.unlocks to authenticated;
create policy unlocks_owner_read on public.unlocks for select using (owner_id = auth.uid());

grant select on public.notifications to authenticated;
create policy notifications_self_read on public.notifications for select using (user_id = auth.uid());

grant select on public.subscriptions to authenticated;
create policy subscriptions_self_read on public.subscriptions for select using (owner_id = auth.uid());

grant select on public.payments to authenticated;
create policy payments_self_read on public.payments for select using (owner_id = auth.uid());

grant select on public.feed, public.my_request_contacts, public.my_unlocks to authenticated;

grant execute on function
  public.set_my_role(public.user_role),
  public.publish_request(uuid, public.transaction_type, public.property_type, int[], text, int, int, text, int, boolean, text, text, int, boolean, boolean),
  public.extend_request(uuid, int),
  public.remove_request(uuid),
  public.close_request(uuid, uuid, int),
  public.register_listen(uuid),
  public.unlock_contact(uuid),
  public.set_unlock_outcome(uuid, text),
  public.report_owner(uuid, uuid, text),
  public.mark_notifications_read(bigint[]),
  public.is_offerer(uuid),
  public.first_name(text),
  public.zone_label(int[], text),
  public.format_fcfa(int),
  public.normalize_phone(text)
to authenticated;

-- Tâches planifiées : réservées au serveur
revoke execute on function public.expire_requests(), public.remind_expiring(), public.daily_listen_digest(),
  public.notify_user(uuid, text, text, text, jsonb, text) from authenticated;

-- =====================================================================
-- Stockage des vocaux (bucket privé)
-- Chemin : <user_id>/<request_id>.<ext>
-- =====================================================================
do $storage$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('voice-requests', 'voice-requests', false, 5242880,
            array['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac', 'audio/webm', 'audio/ogg', 'audio/mpeg', 'audio/wav'])
    on conflict (id) do nothing;

    execute $p$
      create policy "voice_upload_own_folder" on storage.objects for insert to authenticated
      with check (bucket_id = 'voice-requests' and (storage.foldername(name))[1] = auth.uid()::text)
    $p$;
    execute $p$
      create policy "voice_read_own" on storage.objects for select to authenticated
      using (bucket_id = 'voice-requests' and (storage.foldername(name))[1] = auth.uid()::text)
    $p$;
    execute $p$
      create policy "voice_read_published_by_offerers" on storage.objects for select to authenticated
      using (
        bucket_id = 'voice-requests'
        and public.is_offerer(auth.uid())
        and exists (
          select 1 from public.requests r
          where r.audio_path = storage.objects.name and r.status = 'published' and r.expires_at > now()
        )
      )
    $p$;
  end if;
end
$storage$;

-- Temps réel : le badge de notifications se met à jour en direct
do $rt$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end
$rt$;
