#!/usr/bin/env bash
# Génère le dossier android/ (s'il manque) et y ajoute ce dont Dëkk a besoin :
# micro, Internet, ouverture de WhatsApp, version Android minimale.
# Usage : cd app && bash tool/prepare_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create . --platforms=android --org sn.dekk --project-name dekk
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
python3 - "$MANIFEST" <<'PY'
import re, sys
path = sys.argv[1]
xml = open(path, encoding="utf-8").read()
perms = [
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.POST_NOTIFICATIONS",
]
for p in perms:
    if p not in xml:
        xml = xml.replace("<application", f'<uses-permission android:name="{p}"/>\n    <application', 1)
# Android 11+ : déclarer les applications que l'on ouvre (WhatsApp via https)
if "android.intent.action.VIEW" not in xml.split("<application")[0] and "<queries>" not in xml:
    xml = xml.replace("<application", """<queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <package android:name="com.whatsapp"/>
        <package android:name="com.whatsapp.w4b"/>
    </queries>
    <application""", 1)
xml = re.sub(r'android:label="[^"]*"', 'android:label="Dëkk"', xml, count=1)
open(path, "w", encoding="utf-8").write(xml)
print("AndroidManifest.xml mis à jour")
PY

for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] || continue
  sed -i -E 's/minSdk( =|Version)? *flutter\.minSdkVersion/minSdk = 23/' "$f"
  sed -i -E 's/minSdkVersion +flutter\.minSdkVersion/minSdkVersion 23/' "$f"
  echo "$f : minSdk 23"
done
