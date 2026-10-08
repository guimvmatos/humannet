#!/usr/bin/env python3
"""Gera android/app/src/main/res/values/firebase.xml a partir do
google-services.json (variável GS_JSON), como o plugin google-services faria.

Assim o arquivo do Firebase não precisa ficar no repositório público: no CI ele
vem do segredo GOOGLE_SERVICES_JSON.
"""
import json
import os
import pathlib
import sys
from xml.sax.saxutils import escape

PACKAGE = "social.humannet.humannet"

raw = os.environ.get("GS_JSON", "").strip()
if not raw:
    sys.exit("GS_JSON vazio")
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("::error title=firebase::GOOGLE_SERVICES_JSON não é um JSON válido "
          "(cole o conteúdo inteiro do google-services.json).")
    sys.exit(1)

clients = [
    c for c in data.get("client", [])
    if c.get("client_info", {}).get("android_client_info", {}).get("package_name") == PACKAGE
]
if not clients:
    print(f"::error title=firebase::Nenhum app Android '{PACKAGE}' no google-services.json. "
          "Registre o app no Firebase com esse nome de pacote.")
    sys.exit(1)
client = clients[0]
project = data["project_info"]
key = client["api_key"][0]["current_key"]
values = {
    "google_app_id": client["client_info"]["mobilesdk_app_id"],
    "gcm_defaultSenderId": project["project_number"],
    "google_api_key": key,
    "google_crash_reporting_api_key": key,
    "project_id": project["project_id"],
}
if project.get("storage_bucket"):
    values["google_storage_bucket"] = project["storage_bucket"]

out = pathlib.Path("android/app/src/main/res/values/firebase.xml")
out.parent.mkdir(parents=True, exist_ok=True)
lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
for k, v in values.items():
    lines.append(f'    <string name="{k}" translatable="false">{escape(str(v))}</string>')
lines.append("</resources>")
out.write_text("\n".join(lines) + "\n")
print(f"firebase.xml gerado para {PACKAGE} (projeto {project['project_id']}).")
