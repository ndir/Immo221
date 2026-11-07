// Configuration de la page web Dëkk.
// Remplacez les valeurs ci-dessous par celles de votre projet Supabase
// (Project Settings › API). La clé « anon » est publique par conception :
// la sécurité repose sur les règles RLS de la base.
window.DEKK_CONFIG = {
  supabaseUrl: "https://VOTRE-PROJET.supabase.co",
  supabaseAnonKey: "VOTRE_CLE_ANON",
  // Lien Google Play de l'application (laisser vide tant qu'elle n'est pas publiée)
  playStoreUrl: "",
  // Adresse affichée comme lien de suivi
  siteUrl: "https://dekk.sn",
  // true = démonstration sans serveur (données fictives). Aussi activable avec ?demo=1
  demo: false,
};
