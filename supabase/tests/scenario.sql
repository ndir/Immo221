-- Scénario de bout en bout sur la base locale (après supabase_stub.sql + migrations).
-- Chaque vérification lève une exception si le résultat n'est pas celui attendu.
\set ON_ERROR_STOP on

-- Trois utilisateurs : Awa (demandeuse), une agence, un démarcheur
insert into auth.users (id, phone, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', '221771234534', '{"display_name":"Awa Diop"}'),
  ('00000000-0000-0000-0000-00000000000b', '221770000001', '{"display_name":"Ibrahima Sarr"}'),
  ('00000000-0000-0000-0000-00000000000c', '221770000002', '{"display_name":"Moussa Diallo"}');

do $$ begin
  assert (select phone from profiles where id = '00000000-0000-0000-0000-00000000000a') = '+221771234534',
    'le profil doit être créé avec le numéro au format E.164';
end $$;

-- ---------- L'agence configure son compte ----------
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select set_my_role('agency');
update profiles set agency_name = 'Immo Sacré-Cœur' where id = auth.uid();
insert into owner_subscriptions (zone_id, transaction)
  select id, 'location' from zones where name in ('Mermoz', 'Sacré-Cœur');

-- tentative de devenir admin : refusée
do $$ begin
  perform set_my_role('admin');
  raise exception 'set_my_role(admin) aurait dû échouer';
exception when others then
  if sqlerrm <> 'forbidden_role' then raise; end if;
end $$;

-- tentative de se vérifier soi-même : refusée (pas de droit sur la colonne)
do $$ begin
  update profiles set is_verified = true where id = auth.uid();
  raise exception 'is_verified ne doit pas être modifiable';
exception when insufficient_privilege then null;
end $$;

-- ---------- Le démarcheur suit Mermoz, tous types ----------
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select set_my_role('broker');
insert into owner_subscriptions (zone_id) select id from zones where name = 'Mermoz';

-- ---------- Awa dépose une demande ----------
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- chemin audio hors de son dossier : refusé
do $$ begin
  insert into requests (audio_path) values ('autre/x.m4a');
  raise exception 'insert hors dossier aurait dû échouer';
exception when insufficient_privilege then null;
end $$;

insert into requests (id, audio_path, source)
values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111.m4a', 'web');

-- Le serveur (process-voice) remplit la fiche
reset role;
update requests set status = 'draft', transcript = 'Salam, dama bëgg un appartement deux chambres vers Mermoz ou Sacré-Cœur...',
  transaction = 'location', property = 'appartement',
  zone_ids = (select array_agg(id order by name) from zones where name in ('Mermoz', 'Sacré-Cœur')),
  budget_max = 300000, budget_period = 'mois', bedrooms_min = 2, move_in = 'le mois prochain',
  summary = 'Appartement 2 ch. à Mermoz ou Sacré-Cœur, max 300 000 F/mois'
where id = '11111111-1111-1111-1111-111111111111';

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Awa ne peut pas modifier directement sa demande (passage obligé par les fonctions)
do $$ begin
  update requests set status = 'published' where id = '11111111-1111-1111-1111-111111111111';
  raise exception 'update direct aurait dû échouer';
exception when insufficient_privilege then null;
end $$;

select status, expires_at > now() + interval '14 days' as expire_ok from publish_request(
  '11111111-1111-1111-1111-111111111111', 'location', 'appartement',
  (select array_agg(id order by name) from zones where name in ('Mermoz', 'Sacré-Cœur')),
  null, null, 300000, 'mois', 2, null, 'le mois prochain',
  'Appartement 2 ch. à Mermoz ou Sacré-Cœur, max 300 000 F/mois', 15, true, false);

-- ---------- Notifications envoyées à la publication ----------
reset role;
do $$ begin
  assert (select count(*) from notifications where type = 'new_request') = 2,
    'les deux offreurs abonnés doivent être alertés';
  assert (select count(*) from notifications where type = 'new_request' and priority = 'high') = 2,
    'une demande urgente doit partir en priorité haute';
  assert (select count(*) from notifications where type = 'request_published'
           and user_id = '00000000-0000-0000-0000-00000000000a') = 1,
    'la demandeuse doit être prévenue de la publication';
end $$;
select user_id, type, title, body from notifications order by id;

-- ---------- L'agence voit la demande dans son fil, sans numéro ----------
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  assert (select count(*) from feed) = 1, 'le fil doit contenir la demande';
  assert (select seeker_first_name from feed) = 'Awa', 'prénom seulement';
  assert (select count(*) from requests) = 0, 'un offreur ne lit pas la table requests';
  assert (select count(*) from profiles) = 1, 'un offreur ne lit que son propre profil';
end $$;

select register_listen('11111111-1111-1111-1111-111111111111');
select register_listen('11111111-1111-1111-1111-111111111111'); -- 2e écoute : non comptée
select unlock_contact('11111111-1111-1111-1111-111111111111') as contact;
-- 2e déblocage : idempotent, pas de double comptage
select (unlock_contact('11111111-1111-1111-1111-111111111111')) ->> 'already_unlocked' as deja;

-- ---------- Awa voit qui l'a contactée ----------
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select contacts_count from requests where id = '11111111-1111-1111-1111-111111111111') = 1,
    'un seul contact compté';
  assert (select listen_count from requests where id = '11111111-1111-1111-1111-111111111111') = 1,
    'une seule écoute comptée';
  assert (select owner_name from my_request_contacts) = 'Immo Sacré-Cœur', 'nom de l''agence';
  assert (select count(*) from notifications where type = 'owner_contacted') = 1,
    'Awa est prévenue du contact';
  assert (select count(*) from feed) = 0, 'un demandeur ne voit pas le fil';
end $$;

-- Awa ne peut pas débloquer (pas offreuse)
do $$ begin
  perform unlock_contact('11111111-1111-1111-1111-111111111111');
  raise exception 'unlock par une demandeuse aurait dû échouer';
exception when others then
  if sqlerrm <> 'not_offerer' then raise; end if;
end $$;

-- Désactive un type de notification puis clôture avec avis
select close_request('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000b', 5);

reset role;
do $$ begin
  assert (select rating_avg from profiles where id = '00000000-0000-0000-0000-00000000000b') = 5.0, 'note enregistrée';
  assert (select status from requests where id = '11111111-1111-1111-1111-111111111111') = 'found', 'demande clôturée';
  assert (select count(*) from notifications where type = 'found_thanks') = 1, 'l''agence est remerciée';
end $$;

-- ---------- Mode payant : un forfait devient obligatoire ----------
update app_settings set free_mode = false;
insert into requests (id, seeker_id, audio_path, status, transaction, zone_ids, expires_at, published_at)
values ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-00000000000a',
        '00000000-0000-0000-0000-00000000000a/2.m4a', 'published', 'terrain',
        (select array_agg(id) from zones where name = 'Thiès'), now() + interval '1 day 12 hours', now());

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  perform unlock_contact('22222222-2222-2222-2222-222222222222');
  raise exception 'sans forfait, le déblocage aurait dû échouer';
exception when others then
  if sqlerrm <> 'subscription_required' then raise; end if;
end $$;
reset role;
insert into subscriptions (owner_id, plan, contacts_left, valid_until)
values ('00000000-0000-0000-0000-00000000000c', 'pro', 30, now() + interval '30 days');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select unlock_contact('22222222-2222-2222-2222-222222222222') ->> 'whatsapp_phone' as numero;
reset role;
do $$ begin
  assert (select contacts_left from subscriptions) = 29, 'un contact décompté du forfait';
end $$;
update app_settings set free_mode = true;

-- ---------- Tâches planifiées ----------
do $$ begin
  assert remind_expiring() = 1, 'un rappel d''expiration';
  assert remind_expiring() = 0, 'pas de second rappel';
end $$;
update requests set expires_at = now() - interval '1 minute' where id = '22222222-2222-2222-2222-222222222222';
do $$ begin
  assert expire_requests() = 1, 'la demande expirée passe en expired';
end $$;

-- ---------- Signalements : 3 signalements suspendent ----------
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-0000000000d1', '221770000011'),
  ('00000000-0000-0000-0000-0000000000d2', '221770000012');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select report_owner('00000000-0000-0000-0000-00000000000c', null, 'insistant');
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
select report_owner('00000000-0000-0000-0000-00000000000c');
reset role;
do $$ begin
  assert not (select is_suspended from profiles where id = '00000000-0000-0000-0000-00000000000c'), '2 signalements : pas encore suspendu';
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
select report_owner('00000000-0000-0000-0000-00000000000c');
reset role;
do $$ begin
  assert (select is_suspended from profiles where id = '00000000-0000-0000-0000-00000000000c'), '3 signalements : suspendu';
end $$;

-- ---------- Stockage : accès aux vocaux ----------
insert into storage.objects (bucket_id, name) values
  ('voice-requests', '00000000-0000-0000-0000-00000000000a/11111111-1111-1111-1111-111111111111.m4a');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  -- la demande 1 est clôturée : l'agence n'y a plus accès
  assert (select count(*) from storage.objects) = 0, 'vocal d''une demande clôturée inaccessible';
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  assert (select count(*) from storage.objects) = 1, 'la demandeuse accède à son vocal';
end $$;
reset role;

select format_fcfa(300000) as f1, format_fcfa(25000000) as f2, format_fcfa(1500000) as f3;
\echo 'SCENARIO OK'
