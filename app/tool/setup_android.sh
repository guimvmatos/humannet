#!/usr/bin/env bash
# Gera a pasta android/ (uma vez) e aplica os ajustes que o projeto precisa.
# Depois de rodar localmente, faça commit de android/.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --platforms=android --org social.humannet --project-name humannet .
fi

python3 - <<'PY'
import pathlib, re

app = pathlib.Path("android/app")

# 1) Permissão de internet também no build de release.
main = app / "src/main/AndroidManifest.xml"
s = main.read_text()
if "android.permission.INTERNET" not in s:
    s = re.sub(r"(<manifest[^>]*>)",
               r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
               s, count=1)
    main.write_text(s)

# 2) Em debug, permitir HTTP sem TLS só para o host local (emulador/dev).
debug = app / "src/debug"
(debug / "res/xml").mkdir(parents=True, exist_ok=True)
(debug / "res/xml/network_security_config.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">10.0.2.2</domain>
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
""")
(debug / "AndroidManifest.xml").write_text("""<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:networkSecurityConfig="@xml/network_security_config"/>
</manifest>
""")

# 3) flutter_secure_storage exige minSdk >= 24.
for name in ("build.gradle.kts", "build.gradle"):
    f = app / name
    if f.exists():
        g = f.read_text()
        g = g.replace("minSdk = flutter.minSdkVersion", "minSdk = maxOf(24, flutter.minSdkVersion)")
        g = g.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion Math.max(24, flutter.minSdkVersion)")
        f.write_text(g)

# 4) Assinatura de release com chave própria, se android/key.properties existir
#    (o CI cria a partir dos segredos ANDROID_*). Sem ela, usa a chave de debug.
kts = app / "build.gradle.kts"
if kts.exists():
    g = kts.read_text()
    if 'create("release")' not in g:
        g = g.replace("    buildTypes {", '''    signingConfigs {
        create("release") {
            val ks = rootProject.file("key.properties")
            if (ks.exists()) {
                val p = Properties().apply { ks.inputStream().use { load(it) } }
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
                storeFile = file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
            }
        }
    }

    buildTypes {''', 1)
        g = g.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (rootProject.file("key.properties").exists()) '
            'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
        )
        # `java` dentro de android {} é a extensão do Gradle, não o pacote:
        # importar Properties no topo do script.
        if "import java.util.Properties" not in g:
            g = "import java.util.Properties\n\n" + g
        kts.write_text(g)

# 5) Nome exibido no Android.
main_manifest = app / "src/main/AndroidManifest.xml"
m = main_manifest.read_text()
m = m.replace('android:label="humannet"', 'android:label="HumanNet"')
main_manifest.write_text(m)
PY

echo "android/ pronto."
