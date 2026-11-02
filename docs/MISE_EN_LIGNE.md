# Mise en ligne de Dëkk, pas à pas

Compter une demi-journée pour tout configurer la première fois. Les étapes 1 à 6 suffisent pour que la **page web** fonctionne ; les étapes 7 et 8 ajoutent l'**application** et les **notifications push**.

Les prix indiqués sont des ordres de grandeur ; vérifiez-les sur le site de chaque service au moment de l'inscription.

---

## 1. Créer le projet Supabase

1. Créez un compte sur [supabase.com](https://supabase.com) puis **New project**.
2. Nom : `dekk`. Région : la plus proche du Sénégal parmi celles proposées (Europe de l'Ouest). Notez le mot de passe de la base.
3. Dans **Project Settings › API**, notez :
   - **Project URL** (`https://xxxx.supabase.co`)
   - la clé **anon public** (utilisée par l'app et la page web)
   - la clé **service_role** (secrète : ne jamais la mettre dans l'app ni la page web)

L'offre gratuite suffit pour la bêta.

## 2. Créer la base de données

**Option simple (sans outil à installer)** : dans **SQL Editor**, collez puis exécutez dans l'ordre :
1. `supabase/migrations/20261102000001_schema.sql`
2. `supabase/migrations/20261102000002_zones.sql`

**Option ligne de commande** (recommandée ensuite) :
```bash
npm install -g supabase        # ou : brew install supabase/tap/supabase
supabase login
supabase link --project-ref xxxx   # xxxx = identifiant dans l'URL du projet
supabase db push
```

Ne jamais exécuter `supabase/tests/supabase_stub.sql` sur le vrai projet : il ne sert qu'aux tests locaux.

## 3. Activer la connexion par SMS

1. **Authentication › Sign In / Providers › Phone** : activez.
2. Choisissez un fournisseur SMS (Twilio, Vonage, MessageBird…) et collez ses identifiants. Twilio couvre le Sénégal ; un SMS coûte quelques dizaines de FCFA.
3. Modèle du message : `Votre code Dëkk : {{ .Code }}`.
4. Pour tester sans payer de SMS : dans la même page, ajoutez des **numéros de test** avec un code fixe (par ex. `221770000001=123456`).

## 4. Obtenir la clé OpenAI

1. Créez un compte sur [platform.openai.com](https://platform.openai.com), ajoutez un moyen de paiement et un petit crédit (5 à 10 $ suffisent pour des milliers de vocaux).
2. **API keys › Create new secret key**. Copiez la clé (`sk-...`).

Coût indicatif : environ 0,003 $ par minute de vocal transcrite + moins de 0,001 $ pour l'extraction.

## 5. Déployer les fonctions serveur

```bash
# Secrets (une seule fois)
supabase secrets set OPENAI_API_KEY=sk-...
supabase secrets set WEBHOOK_SECRET=$(openssl rand -hex 24)   # notez la valeur affichée par: supabase secrets list

# Déploiement
supabase functions deploy process-voice
supabase functions deploy send-push --no-verify-jwt
supabase functions deploy push-digest --no-verify-jwt
```

Facultatif : `OPENAI_TRANSCRIBE_MODEL` et `OPENAI_EXTRACT_MODEL` changent les modèles utilisés (par défaut `gpt-4o-mini-transcribe` et `gpt-4o-mini`).

## 6. Mettre en ligne la page web

1. Ouvrez `web/config.js` et remplacez `supabaseUrl` et `supabaseAnonKey`.
2. Hébergez le dossier `web/` sur un hébergeur de sites statiques gratuit : Netlify (glisser-déposer du dossier), Cloudflare Pages, Vercel ou GitHub Pages.
3. Nom de domaine : un `.sn` se réserve auprès d'un bureau d'enregistrement agréé par le NIC Sénégal ; sinon un `.com`. Mettez l'adresse finale dans `siteUrl`.
4. Dans Supabase, **Authentication › URL Configuration** : mettez cette adresse comme **Site URL**.

Test : ouvrez la page sur un téléphone, enregistrez un vocal, validez avec un numéro de test, vérifiez la fiche puis publiez. La demande apparaît dans **Table Editor › requests**.

Le micro du navigateur exige une adresse en **https** (c'est le cas sur ces hébergeurs).

## 7. Compiler l'application Android

### Avec GitHub (sans rien installer)
1. Dans le dépôt GitHub : **Settings › Secrets and variables › Actions**, ajoutez `SUPABASE_URL` et `SUPABASE_ANON_KEY`.
2. À chaque envoi de code, l'onglet **Actions** compile l'application. Téléchargez l'APK dans l'artefact `dekk-apk` du dernier passage, puis installez-le sur un téléphone Android (autoriser les sources inconnues).

### Sur votre ordinateur
1. Installez Flutter ([docs.flutter.dev/get-started](https://docs.flutter.dev/get-started/install)) et Android Studio.
2. Puis :
```bash
cd app
bash tool/prepare_android.sh      # génère android/ et ajoute micro, WhatsApp, Android 6+
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
```
3. APK à distribuer : `flutter build apk --release --dart-define=...` (même paramètres).

### Publier sur Google Play
Compte développeur Google Play (frais uniques d'environ 25 $), puis créez une clé de signature ([guide officiel](https://docs.flutter.dev/deployment/android)). Une fois publiée, mettez le lien dans `web/config.js` (`playStoreUrl`) : la page web le proposera aux demandeurs.

## 8. Activer les notifications push

Sans cette étape, l'app fonctionne avec son centre de notifications intégré ; seules les alertes sur l'écran verrouillé manquent.

1. Créez un projet sur [console.firebase.google.com](https://console.firebase.google.com).
2. Reliez l'app : `dart pub global activate flutterfire_cli` puis, dans `app/`, `flutterfire configure` (choisissez Android ; identifiant `sn.dekk.dekk`).
3. **Paramètres du projet › Comptes de service › Générer une nouvelle clé privée** : un fichier JSON se télécharge.
4. Donnez-le aux fonctions :
   ```bash
   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chemin/vers/cle.json)"
   ```
5. **Déclencheur d'envoi** : dans Supabase, **Database › Webhooks › Create** :
   - Table `notifications`, événement **Insert**
   - Type **Supabase Edge Functions**, fonction `send-push`, méthode POST
   - En-tête HTTP : `x-webhook-secret` = la valeur de `WEBHOOK_SECRET`

## 9. Tâches automatiques

Dans **Database › Extensions**, activez `pg_cron` et `pg_net`, puis exécutez dans le SQL Editor (remplacez `xxxx` et `SECRET`). Les heures sont celles de Dakar (UTC).

```sql
select cron.schedule('dekk-expire', '*/15 * * * *', $$select public.expire_requests()$$);
select cron.schedule('dekk-rappel-expiration', '0 9 * * *', $$select public.remind_expiring()$$);
select cron.schedule('dekk-resume-ecoutes', '0 19 * * *', $$select public.daily_listen_digest()$$);

select cron.schedule('dekk-push-matin', '5 7 * * *', $$
  select net.http_post(
    url := 'https://xxxx.supabase.co/functions/v1/push-digest',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', 'SECRET'),
    body := '{}'::jsonb)
$$);
select cron.schedule('dekk-push-soir', '0 18 * * *', $$
  select net.http_post(
    url := 'https://xxxx.supabase.co/functions/v1/push-digest',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', 'SECRET'),
    body := '{}'::jsonb)
$$);
```

## 10. Administration courante (SQL Editor)

```sql
-- Vérifier une agence (badge « vérifiée »)
update profiles set is_verified = true where phone = '+221771234567';

-- Lever une suspension après examen des signalements
update profiles set is_suspended = false where phone = '+221...';
select * from reports order by created_at desc;

-- Ajouter un quartier
insert into zones (name, city, region, aliases) values ('Kounoune', 'Rufisque', 'Dakar', '{}');

-- Fin du lancement gratuit (le jour où les forfaits sont prêts)
update app_settings set free_mode = false;

-- Annonce à tous les offreurs
select notify_user(id, 'announcement', 'Les forfaits arrivent', 'L''accès reste gratuit jusqu''au ...')
from profiles where role in ('owner', 'broker', 'agency');
```

## 11. Avant l'ouverture au public

- **Données personnelles** : la voix et le numéro de téléphone sont des données personnelles. Faites une déclaration auprès de la CDP (Commission de protection des Données Personnelles du Sénégal) et publiez une politique de confidentialité.
- **Qualité de la transcription** : testez sur 50 vrais vocaux (français, wolof, mélange) et regardez la colonne `ai_raw` des demandes pour repérer les erreurs fréquentes.
- **Photo d'accueil** : vérifiez que vous avez le droit d'utiliser la photo du monument (`web/assets/accueil.png`, `app/assets/accueil.png`), ou remplacez-la par la vôtre.

## Ce qui n'est pas encore inclus

- **Paiements Wave et Orange Money** : tables prêtes (`payments`, `subscriptions`), intégration à faire avant la fin du lancement gratuit (comptes marchands avec NINEA et RCCM requis).
- **Dépôt d'une demande par WhatsApp** (robot) : possible plus tard via WhatsApp Business Platform, avec le même traitement IA.
- **Lien de suivi par SMS** : la page web affiche le lien de suivi ; l'envoi automatique par SMS demandera un fournisseur SMS côté serveur.
- **iOS** : le code est compatible, mais seule la version Android est préparée.
