#!/usr/bin/env bash
# Fase 3 — Crea i lanciatori di Outlook, Word, Excel e Teams con le icone
# originali e li aggancia alla barra delle applicazioni di KDE Plasma.
#
# Idempotente: rigenera lanciatori/icone a ogni esecuzione e aggiunge al
# pannello solo le voci mancanti. Fa backup della config del pannello e
# riavvia plasmashell solo se l'ha modificata.
#
# Come funziona il lancio: ogni .desktop chiama ~/.local/bin/winboat-app,
# che legge credenziali e porta RDP a runtime dai file di WinBoat (nessun
# segreto duplicato) e apre l'app come finestra RemoteApp via FreeRDP.
# Programma e argomenti di ogni app vengono risolti ADESSO dal Guest API
# (gli exe classici usano il percorso diretto, le app UWP come Teams
# passano da explorer.exe + shell:AppsFolder\...).
set -euo pipefail

echo "== Fase 3: lanciatori in barra =="

api_port=$(docker port WinBoat 7148/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}')
[ -n "$api_port" ] || { echo "ERRORE: VM spenta — esegui prima la fase 2"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -s -m 30 "http://127.0.0.1:$api_port/apps" -o "$TMP/apps.json"
[ -s "$TMP/apps.json" ] || { echo "ERRORE: Guest API senza risposta"; exit 1; }

# Estrae icone e coordinate di lancio; genera lo script winboat-app.
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 - "$TMP/apps.json" "$KIT_DIR" <<'EOF'
import json, base64, os, sys, pathlib

apps = json.load(open(sys.argv[1]))
kit = pathlib.Path(sys.argv[2])
home = pathlib.Path.home()
# chiave breve -> (nome nel Guest API, etichetta in barra)
want = {
    "outlook": ("Microsoft Outlook", "Outlook"),
    "word":    ("Microsoft Word",    "Word"),
    "excel":   ("Microsoft Excel",   "Excel"),
    "teams":   ("Microsoft Teams",   "Teams"),
}
byname = {a["Name"]: a for a in apps}

icondir = home/".local/share/icons/hicolor/32x32/apps"
icondir.mkdir(parents=True, exist_ok=True)
appdir = home/".local/share/applications"
appdir.mkdir(parents=True, exist_ok=True)

# Il Guest API di WinBoat (fino alla 0.9) non enumera il nuovo Teams MSIX:
# coordinate di lancio standard del pacchetto + icona fornita dal kit.
fallbacks = {
    "teams": {
        "Path": "explorer.exe",
        "Args": r"shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams",
        "IconFile": kit/"resources"/"teams.png",
    },
}

cases, missing = [], []
for key, (name, label) in want.items():
    a = byname.get(name)
    if a:
        (icondir/f"winboat-{key}.png").write_bytes(base64.b64decode(a["Icon"]))
        prog, args = a["Path"], a.get("Args", "")
    elif key in fallbacks:
        fb = fallbacks[key]
        if fb["IconFile"].exists():
            (icondir/f"winboat-{key}.png").write_bytes(fb["IconFile"].read_bytes())
        prog, args = fb["Path"], fb["Args"]
        print(f"{label}: assente dalla lista WinBoat, uso coordinate MSIX standard")
    else:
        missing.append(name); continue
    cases.append(f'    {key}) NAME="{name}"; PROG=\'{prog}\'; ARGS=\'{args}\' ;;')
    (appdir/f"winboat-{key}.desktop").write_text(f"""[Desktop Entry]
Type=Application
Name={label}
GenericName={name} (WinBoat)
Comment={name} nella VM Windows di WinBoat
Exec={home}/.local/bin/winboat-app {key}
Icon=winboat-{key}
Categories=Office;
StartupNotify=true
StartupWMClass=winboat-{name}
""")
    print(f"lanciatore: {label:8s} ← {prog} {args}")

launcher = home/".local/bin/winboat-app"
launcher.parent.mkdir(parents=True, exist_ok=True)
launcher.write_text("""#!/usr/bin/env bash
# Generato da winboat-office-kit/03-create-taskbar-launchers.sh — non modificare a mano:
# rieseguire la fase 3 per rigenerarlo. Lancia un'app della VM WinBoat come
# finestra RemoteApp, leggendo credenziali e porta a runtime dai file di WinBoat.
set -eu
case "${1:-}" in
""" + "\n".join(cases) + """
    *) echo "Uso: winboat-app <chiave>" >&2; exit 2 ;;
esac
COMPOSE="$HOME/.winboat/docker-compose.yml"
U=$(sed -n 's/^[[:space:]]*USERNAME:[[:space:]]*"\\{0,1\\}\\([^"]*\\)"\\{0,1\\}$/\\1/p' "$COMPOSE" | head -1)
P=$(sed -n 's/^[[:space:]]*PASSWORD:[[:space:]]*"\\{0,1\\}\\([^"]*\\)"\\{0,1\\}$/\\1/p' "$COMPOSE" | head -1)
PORT=$(docker port WinBoat 3389/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}')
if [ -z "$PORT" ]; then
    notify-send -i dialog-error "WinBoat" "La VM Windows non è in esecuzione: avviala da WinBoat." 2>/dev/null || true
    exit 1
fi
exec xfreerdp /u:"$U" /p:"$P" /v:127.0.0.1 /port:"$PORT" /cert:ignore \\
    +clipboard /sound:sys:pulse /microphone:sys:pulse \\
    /floatbar /compression -wallpaper /scale-desktop:100 \\
    /wm-class:"winboat-$NAME" \\
    "/app:program:$PROG,name:$NAME,cmd:$ARGS"
""")
launcher.chmod(0o755)

if missing:
    print("ATTENZIONE — non installate nella VM (esegui la fase 2):", ", ".join(missing))
    sys.exit(3)
EOF

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# --- Aggancio alla barra delle applicazioni (Plasma icontasks) -------------------------
CFG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
line=$(grep -n '^launchers=.*applications:' "$CFG" | sort -t: -k2 --key=2,2 | awk -F: 'length($0)>max{max=length($0);n=$1}END{print n}')
[ -n "$line" ] || { echo "ERRORE: nessuna task bar con lanciatori trovata in $CFG"; exit 1; }

changed=0
for key in outlook word excel teams; do
    if ! sed -n "${line}p" "$CFG" | grep -q "winboat-$key.desktop"; then
        [ "$changed" -eq 0 ] && cp "$CFG" "$CFG.bak-winboat-kit"
        sed -i "${line}s|\$|,applications:winboat-$key.desktop|" "$CFG"
        changed=1
        echo "aggiunto alla barra: $key"
    fi
done

if [ "$changed" -eq 1 ]; then
    systemctl --user restart plasma-plasmashell.service
    echo "Pannello aggiornato (backup: $CFG.bak-winboat-kit)"
else
    echo "Barra già completa: nessuna modifica"
fi

echo "Fase 3 completata."
