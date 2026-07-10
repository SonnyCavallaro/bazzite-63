#!/usr/bin/env bash
# Fase 2 — Installa la suite Office e Teams DENTRO la VM Windows, se mancanti.
#
# Idempotente: interroga il Guest API di WinBoat (/apps) e installa via
# winget (RemoteApp PowerShell) solo ciò che non risulta già presente.
# Richiede: VM creata (fase 1) e sessione desktop attiva (xfreerdp apre
# una finestra temporanea con la console dell'installazione).
# L'attivazione di Office (login Microsoft 365) resta manuale al primo
# avvio di una app: winget installa, non attiva.
set -euo pipefail

echo "== Fase 2: Office + Teams nella VM =="

# --- VM accesa -------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -qx WinBoat; then
    echo "Avvio la VM Windows..."
    docker start WinBoat >/dev/null
fi

api_port() { docker port WinBoat 7148/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}'; }
rdp_port() { docker port WinBoat 3389/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}'; }

echo -n "Attendo il Guest API"
for _ in $(seq 1 60); do
    P=$(api_port)
    if [ -n "$P" ] && curl -s -m 3 "http://127.0.0.1:$P/health" | grep -q ok; then echo " — pronto"; break; fi
    echo -n "."; sleep 5
done
P=$(api_port)
curl -s -m 3 "http://127.0.0.1:$P/health" | grep -q ok || { echo "ERRORE: Guest API non raggiungibile"; exit 1; }

apps_json() { curl -s -m 30 "http://127.0.0.1:$(api_port)/apps"; }
has_app()   { apps_json | grep -q "\"$1\""; }

# --- Lancio comandi nella VM via RemoteApp -----------------------------------------
COMPOSE="$HOME/.winboat/docker-compose.yml"
VM_USER=$(sed -n 's/^[[:space:]]*USERNAME:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$COMPOSE" | head -1)
VM_PASS=$(sed -n 's/^[[:space:]]*PASSWORD:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$COMPOSE" | head -1)

vm_winget_install() { # $1 = id winget
    setsid -f xfreerdp /u:"$VM_USER" /p:"$VM_PASS" /v:127.0.0.1 /port:"$(rdp_port)" \
        /cert:ignore /compression -wallpaper \
        "/app:program:C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe,name:winget,cmd:-NoProfile -Command winget install -e --id $1 --source winget --accept-source-agreements --accept-package-agreements" \
        >/dev/null 2>&1 < /dev/null
}

wait_app() { # $1 = nome app nel Guest API, $2 = minuti massimi
    echo -n "Attendo '$1' (max $2 min)"
    for _ in $(seq 1 $(( $2 * 3 ))); do
        if has_app "$1"; then echo " — installato"; return 0; fi
        echo -n "."; sleep 20
    done
    echo; echo "ERRORE: '$1' non comparso entro $2 minuti"; return 1
}

# --- Office (Microsoft 365 Apps) ----------------------------------------------------
if has_app "Microsoft Word"; then
    echo "Suite Office: già installata"
else
    echo "Installo Microsoft 365 Apps (winget Microsoft.Office)..."
    vm_winget_install Microsoft.Office
    wait_app "Microsoft Word" 40
fi

# --- Teams ---------------------------------------------------------------------------
# Il Guest API di WinBoat (fino alla 0.9) NON enumera il nuovo Teams MSIX,
# quindi la presenza non è verificabile da /apps. winget è idempotente
# (se già installato esce con "No available upgrade"): si lancia sempre e
# si attende la fine del processo RemoteApp, con timeout.
echo "Installo/aggiorno Microsoft Teams (winget, idempotente)..."
vm_winget_install Microsoft.Teams
echo -n "Attendo la fine di winget (max 15 min)"
for _ in $(seq 1 60); do
    pgrep -f 'xfreerdp.*name:winget' >/dev/null || break
    echo -n "."; sleep 15
done
echo
# La sessione RemoteApp può restare appesa dopo la fine del comando: chiusura.
pkill -f 'xfreerdp.*name:winget' 2>/dev/null || true

echo "Fase 2 completata."
