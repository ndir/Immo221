# Immo221 · Dëkk

Application de mise en relation immobilière au Sénégal. Le demandeur décrit son besoin **en note vocale** ; l'IA le transcrit et remplit une fiche ; les propriétaires, démarcheurs et agences le contactent **directement sur WhatsApp**.

> « Dëkk » est un nom provisoire, facile à remplacer (textes de l'app et de la page web).

## Ce que contient ce dépôt

| Dossier | Contenu |
| --- | --- |
| `supabase/migrations/` | Base de données : tables, sécurité (RLS), fonctions métier, notifications, zones de tout le Sénégal |
| `supabase/functions/` | Fonctions serveur : `process-voice` (transcription + extraction IA), `send-push` et `push-digest` (notifications) |
| `supabase/tests/` | Scénario SQL de bout en bout et tests de la logique serveur |
| `web/` | Page web du demandeur, **sans installation** : vocal → numéro → fiche → publication → suivi |
| `app/` | Application Flutter (Android d'abord) : parcours Demandeur et Offreur |
| `docs/MISE_EN_LIGNE.md` | **Guide pas à pas** pour créer les comptes et tout mettre en ligne |
| `.github/workflows/ci.yml` | Vérifications automatiques à chaque envoi + compilation de l'APK Android |

## Fonctionnement

```
Demandeur (page web ou app)                      Offreur (app)
  │ enregistre un vocal                            │ choisit ses zones d'alerte
  ▼                                                ▼
Supabase Storage ──► process-voice ──► OpenAI      fil des demandes (vue « feed »)
  (audio privé)        transcription + fiche JSON   │ écoute le vocal, lit la fiche
  ▼                                                ▼
fiche vérifiée ──► publish_request ──► alertes ──► unlock_contact
                                      (notifications   │ numéro + message pré-rempli
                                       + push FCM)     ▼
                                                    WhatsApp (wa.me)
```

- **Gratuit au lancement** : `app_settings.free_mode = true`. Le jour où les forfaits démarrent, passer à `false` : un forfait actif (table `subscriptions`) devient nécessaire pour contacter un demandeur. Les tables de paiement Wave / Orange Money sont prêtes ; l'intégration des paiements est l'étape suivante.
- **Partout au Sénégal** : 60 quartiers et villes de départ (Dakar et banlieue, Thiès, Mbour, Saly, Touba, Saint-Louis, Ziguinchor, Kaolack…), avec leurs variantes orales (« Parcelles », « PA », « Sacré Coeur »…).
- **Garde-fous** : 5 contacts maximum par demande, 30 déblocages par jour et par offreur, suspension automatique après 3 signalements, expiration des demandes, vocaux accessibles uniquement pendant que la demande est en ligne.
- **Notifications** : centre in-app en temps réel + push Firebase, avec heures calmes (22 h – 7 h), mode résumé matin et soir, plafond quotidien.

## Lancer les vérifications

```bash
# Base de données (Postgres 15+ local)
PGUSER=postgres ./supabase/tests/run_local.sh

# Logique serveur (Node 22+)
node --experimental-strip-types --test supabase/tests/functions.test.ts

# Page web en mode démonstration (sans serveur) : ouvrir http://localhost:8765/?demo=1
cd web && python3 -m http.server 8765

# Application
cd app && bash tool/prepare_android.sh && flutter pub get && flutter test
```

En mode démonstration, la page web fonctionne avec des données fictives (code SMS : `123456`).

## Mise en ligne

Suivre **[docs/MISE_EN_LIGNE.md](docs/MISE_EN_LIGNE.md)**.
