# Mise en ligne de Dëkk, pas à pas

Guide à jour de l'interface Supabase de novembre 2026. Compter une demi-journée la première fois.

- Étapes 1 à 6 : la **page web** fonctionne (dépôt de demandes par vocal).
- Étapes 7 et 8 : l'**application Android** et les **notifications push**.
- Étape 9 : les **tâches automatiques** (expiration des demandes, rappels, résumés).

Les prix sont des ordres de grandeur : vérifiez-les sur le site de chaque service.

Si un menu a changé de nom, le moteur de recherche du tableau de bord Supabase (raccourci **Ctrl + K**, ou **Cmd + K** sur Mac) retrouve n'importe quelle page par son nom.

---

## 1. Créer le projet Supabase

1. Créez un compte sur [supabase.com](https://supabase.com) puis **New project**.
2. Nom : `dekk`. Région : la plus proche du Sénégal parmi celles proposées (Europe de l'Ouest). Notez le mot de passe de la base dans un endroit sûr.
3. Récupérez l'adresse et la clé publique : bouton **Connect** en haut de la page du projet, ou **Project Settings › API Keys**.

| Ce que Supabase affiche | Où l'utiliser |
| --- | --- |
| **Project URL** (`https://xxxx.supabase.co`) | `web/config.js` (`supabaseUrl`) et le secret GitHub `SUPABASE_URL` |
| **Publishable key** (`sb_publishable_...`) | `web/config.js` (`supabaseAnonKey`) et le secret GitHub `SUPABASE_ANON_KEY` |
| **Secret key** (`sb_secret_...`) | Nulle part : les fonctions serveur la reçoivent automatiquement |

La Publishable key remplace l'ancienne clé « anon public » ; les noms `supabaseAnonKey` et `SUPABASE_ANON_KEY` du projet sont seulement d'anciens noms, mettez-y bien la Publishable key. La Secret key remplace l'ancienne « service_role » : ne la mettez jamais dans l'app ni dans la page web.

**Important :** dans **Project Settings › API Keys**, ne désactivez pas les anciennes clés (onglet « Legacy ») pour l'instant. Les fonctions serveur de Dëkk les utilisent encore en interne ; elles seront mises à jour avant que Supabase ne les retire (prévu fin 2026).

L'offre gratuite suffit pour la bêta.

## 2. Créer la base de données

**Option simple (sans rien installer) :** menu de gauche **SQL Editor**, bouton **+** (nouvelle requête). Copiez-collez le contenu de chaque fichier puis cliquez sur **Run**, dans cet ordre :
1. `supabase/migrations/20261102000001_schema.sql`
2. `supabase/migrations/20261102000002_zones.sql`

Vérification : dans **Table Editor**, vous devez voir les tables `requests`, `profiles`, `zones` (60 lignes), `notifications`…

**Option ligne de commande** (utile ensuite pour les fonctions) :
```bash
npm install -g supabase        # ou, sur Mac : brew install supabase/tap/supabase
supabase login
supabase link --project-ref xxxx   # xxxx = l'identifiant dans l'adresse du projet
supabase db push
```

Ne jamais exécuter `supabase/tests/supabase_stub.sql` sur le vrai projet : il ne sert qu'aux tests locaux.

## 3. Activer la connexion par SMS

1. **Authentication › Sign In / Providers › Phone** : activez **Enable Phone provider**.
2. **SMS provider** : choisissez un fournisseur (Twilio, MessageBird, Vonage, Textlocal…) et collez ses identifiants. Twilio couvre le Sénégal ; un SMS coûte quelques dizaines de FCFA. Un compte d'essai Twilio suffit pour commencer.
3. Message : `Votre code Dëkk : {{ .Code }}`.
4. Cliquez sur **Save**.

**Tester sans payer de SMS :** dans la même page, section **Test Phone Numbers and OTPs** :
- saisissez des paires `numéro=code`, numéro au format international **sans +** ni espace, séparées par des virgules : `221770000001=123456,221770000002=123456` ;
- choisissez une date dans **Test OTPs Valid Until** (obligatoire) ;
- **Save**.

Supabase exige qu'un fournisseur SMS soit renseigné même pour les numéros de test (il n'envoie rien à ces numéros). Avant l'ouverture au public, supprimez les numéros de test : quiconque connaît un numéro et son code peut se connecter avec.

## 4. Obtenir la clé OpenAI

1. Créez un compte sur [platform.openai.com](https://platform.openai.com), ajoutez un moyen de paiement et un petit crédit (5 à 10 $ suffisent pour des milliers de vocaux).
2. **API keys › Create new secret key**. Copiez la clé (`sk-...`) : elle ne sera plus affichée.

Coût indicatif : environ 0,003 $ par minute de vocal transcrite, plus moins de 0,001 $ pour remplir la fiche.

## 5. Déployer les fonctions serveur

### 5a. Les secrets

Dans le tableau de bord : **Edge Functions › Secrets** (`supabase.com/dashboard/project/xxxx/functions/secrets`). Ajoutez :

| Key | Value |
| --- | --- |
| `OPENAI_API_KEY` | votre clé `sk-...` |
| `WEBHOOK_SECRET` | une longue suite de caractères au hasard, par exemple générée par un gestionnaire de mots de passe (40 caractères). Notez-la : elle resservira aux étapes 8 et 9 |

Équivalent en ligne de commande : `supabase secrets set OPENAI_API_KEY=sk-... WEBHOOK_SECRET=...`

Facultatif : `OPENAI_TRANSCRIBE_MODEL` et `OPENAI_EXTRACT_MODEL` pour changer de modèle (par défaut `gpt-4o-mini-transcribe` et `gpt-4o-mini`).

`SUPABASE_URL` et les clés Supabase sont fournies automatiquement aux fonctions : ne les ajoutez pas.

### 5b. Le déploiement

Les fonctions partagent du code (dossier `supabase/functions/_shared`) : déployez-les avec la ligne de commande, depuis le dossier `Immo221` :

```bash
supabase functions deploy process-voice
supabase functions deploy send-push --no-verify-jwt
supabase functions deploy push-digest --no-verify-jwt
```

Si Docker n'est pas installé sur votre ordinateur, ajoutez `--use-api` à chaque commande (déploiement sans Docker).

Vérification : **Edge Functions** dans le menu de gauche affiche les trois fonctions.

## 6. Mettre en ligne la page web

1. Ouvrez `web/config.js` et remplacez `supabaseUrl` (Project URL) et `supabaseAnonKey` (Publishable key).
2. Hébergez le dossier `web/` sur un hébergeur de sites statiques gratuit : Netlify (glisser-déposer du dossier sur app.netlify.com), Cloudflare Pages, Vercel ou GitHub Pages.
3. Nom de domaine : un `.sn` se réserve auprès d'un bureau d'enregistrement agréé par le NIC Sénégal ; sinon un `.com`. Mettez l'adresse finale dans `siteUrl` de `web/config.js`.
4. Dans Supabase, **Authentication › URL Configuration** : mettez cette adresse dans **Site URL**, puis **Save**.

Le micro du navigateur exige une adresse en **https**, ce que fournissent ces hébergeurs.

**Test :** ouvrez la page sur un téléphone, enregistrez un vocal, connectez-vous avec un numéro de test (étape 3), vérifiez la fiche puis publiez. La demande apparaît dans **Table Editor › requests** avec le statut `published`. En cas d'échec du traitement, regardez **Edge Functions › process-voice › Logs**.

## 7. Compiler l'application Android

### Avec GitHub (sans rien installer)
1. Dans le dépôt GitHub : **Settings › Secrets and variables › Actions › New repository secret**. Ajoutez `SUPABASE_URL` (Project URL) et `SUPABASE_ANON_KEY` (Publishable key).
2. Onglet **Actions › CI › Run workflow**. Environ 5 minutes plus tard, téléchargez l'APK dans **dekk-apk** en bas de la page du passage terminé.
3. Installez-le sur un téléphone Android (autoriser « Installer des applications inconnues »).

### Sur votre ordinateur
1. Installez Flutter ([docs.flutter.dev/get-started](https://docs.flutter.dev/get-started/install)) et Android Studio.
2. Puis :
```bash
cd app
bash tool/prepare_android.sh      # génère android/ et ajoute micro, WhatsApp, Android 6+
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_...
```
3. APK à distribuer : `flutter build apk --release` avec les mêmes `--dart-define`.

### Publier sur Google Play
1. Compte développeur sur [play.google.com/console](https://play.google.com/console) (frais uniques d'environ 25 $).
2. Clé de signature à créer et à conserver précieusement ([guide Flutter](https://docs.flutter.dev/deployment/android)).
3. Fichier au format Play : `flutter build appbundle` (même `--dart-define`).
4. Fiche de l'app et **politique de confidentialité** en ligne (obligatoire : l'app enregistre la voix et le numéro).
5. Compte personnel récent : **test fermé avec au moins 12 testeurs pendant 14 jours** avant l'accès à la production. Un compte d'organisation (structure juridique et numéro D-U-N-S) n'y est pas soumis.

Une fois l'app publiée, mettez son lien dans `web/config.js` (`playStoreUrl`) : la page web la proposera aux demandeurs.

## 8. Activer les notifications push

Sans cette étape, l'app fonctionne avec son centre de notifications intégré ; seules les alertes sur l'écran verrouillé manquent.

1. Créez un projet sur [console.firebase.google.com](https://console.firebase.google.com).
2. Reliez l'app : `dart pub global activate flutterfire_cli` puis, dans `app/`, `flutterfire configure` (choisissez Android ; identifiant `sn.dekk.dekk`).
3. Firebase : **Paramètres du projet › Comptes de service › Générer une nouvelle clé privée**. Un fichier JSON se télécharge.
4. Supabase : **Edge Functions › Secrets**, ajoutez `FIREBASE_SERVICE_ACCOUNT` avec, comme valeur, **tout le contenu** du fichier JSON (ou en ligne de commande : `supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chemin/vers/cle.json)"`).
5. **Déclencheur d'envoi** : **Database Webhooks** (menu **Integrations**, ou **Database › Webhooks** selon l'affichage) › **Create a new hook** :
   - Name : `envoi-push`
   - Table : `notifications`, événement **Insert**
   - Type : **Supabase Edge Functions**, fonction `send-push`, méthode **POST**
   - HTTP Headers : ajoutez `x-webhook-secret` avec la valeur de `WEBHOOK_SECRET` (étape 5a)
   - **Create webhook**

Test : dans **SQL Editor**, exécutez
```sql
select notify_user(id, 'test', 'Test Dëkk', 'Les notifications fonctionnent') from profiles where phone = '+221770000001';
```
Le téléphone connecté avec ce numéro doit recevoir l'alerte (hors 22 h – 7 h, heures calmes).

## 9. Tâches automatiques

Elles passent les demandes en « expirée », préviennent 2 jours avant l'expiration, et envoient les résumés.

1. **Integrations › Cron** : activez l'intégration (cela installe `pg_cron`).
2. **Database › Extensions** : activez aussi `pg_net` (nécessaire pour appeler une fonction depuis une tâche).
3. Dans **SQL Editor**, exécutez le bloc ci-dessous en remplaçant `xxxx` (identifiant du projet) et `SECRET` (valeur de `WEBHOOK_SECRET`). Les heures sont celles de Dakar (UTC).

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

Les cinq tâches apparaissent ensuite dans **Integrations › Cron**, avec l'historique de chaque exécution.

## 10. Administration courante (SQL Editor)

```sql
-- Vérifier une agence (badge « vérifiée »)
update profiles set is_verified = true where phone = '+221771234567';

-- Voir les signalements, puis lever une suspension après examen
select * from reports order by created_at desc;
update profiles set is_suspended = false where phone = '+221...';

-- Ajouter un quartier
insert into zones (name, city, region, aliases) values ('Kounoune', 'Rufisque', 'Dakar', '{}');

-- Fin du lancement gratuit (le jour où les forfaits sont prêts)
update app_settings set free_mode = false;

-- Annonce à tous les offreurs
select notify_user(id, 'announcement', 'Les forfaits arrivent', 'L''accès reste gratuit jusqu''au ...')
from profiles where role in ('owner', 'broker', 'agency');
```

## 11. Avant l'ouverture au public

- **Numéros de test** : supprimez-les (étape 3).
- **Données personnelles** : la voix et le numéro de téléphone sont des données personnelles. Faites une déclaration auprès de la CDP (Commission de protection des Données Personnelles du Sénégal) et publiez une politique de confidentialité.
- **Qualité de la transcription** : testez sur 50 vrais vocaux (français, wolof, mélange) et regardez la colonne `ai_raw` des demandes pour repérer les erreurs fréquentes.
- **Photo d'accueil** : vérifiez que vous avez le droit d'utiliser la photo du monument (`web/assets/accueil.png`, `app/assets/accueil.png`), ou remplacez-la par la vôtre.

## Ce qui n'est pas encore inclus

- **Paiements Wave et Orange Money** : tables prêtes (`payments`, `subscriptions`), intégration à faire avant la fin du lancement gratuit (comptes marchands avec NINEA et RCCM requis).
- **Dépôt d'une demande par WhatsApp** (robot) : possible plus tard via WhatsApp Business Platform, avec le même traitement IA.
- **Lien de suivi par SMS** : la page web affiche le lien de suivi ; l'envoi automatique par SMS demandera un fournisseur SMS côté serveur.
- **iOS** : le code est compatible, mais seule la version Android est préparée.
