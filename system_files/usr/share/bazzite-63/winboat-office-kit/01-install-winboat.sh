#!/usr/bin/env bash
# Fase 1 — Verifica prerequisiti e installa WinBoat (AppImage) se assente.
#
# Idempotente: rieseguibile senza effetti collaterali.
# Esce con errore chiaro se un prerequisito di sistema manca.
# NON crea la VM Windows: la prima installazione di Windows passa dal
# wizard grafico di WinBoat (interattivo per design). Se la VM manca,
# questo script lo segnala e indica cosa fare.
set -euo pipefail

APPIMAGE="$HOME/.local/bin/WinBoat.AppImage"
DESKTOP="$HOME/.local/share/applications/winboat.desktop"

echo "== Fase 1: WinBoat =="

# --- Prerequisiti di sistema -------------------------------------------------
fail=0
command -v docker >/dev/null || { echo "ERRORE: docker non presente (serve un'immagine Bazzite/Fedora con Docker integrato)"; fail=1; }
docker compose version >/dev/null 2>&1 || { echo "ERRORE: plugin 'docker compose' non presente"; fail=1; }
systemctl is-active -q docker || { echo "ERRORE: servizio docker spento — esegui: sudo systemctl enable --now docker"; fail=1; }
id -nG | tr ' ' '\n' | grep -qx docker || { echo "ERRORE: utente non nel gruppo docker — esegui: sudo usermod -aG docker $USER (poi re-login)"; fail=1; }
[ -e /dev/kvm ] || { echo "ERRORE: /dev/kvm assente — abilita la virtualizzazione nel BIOS"; fail=1; }
command -v xfreerdp >/dev/null || { echo "ERRORE: xfreerdp (FreeRDP) non presente"; fail=1; }
[ "$fail" -eq 0 ] || exit 1
echo "Prerequisiti: OK"

# --- AppImage WinBoat ----------------------------------------------------------
if [ -x "$APPIMAGE" ]; then
    echo "WinBoat già installato: $APPIMAGE"
else
    echo "Scarico l'ultima release di WinBoat..."
    url=$(curl -s https://api.github.com/repos/TibixDev/winboat/releases/latest \
          | grep -oE '"browser_download_url": "[^"]+\.AppImage"' | cut -d'"' -f4 | head -1)
    [ -n "$url" ] || { echo "ERRORE: nessun asset AppImage nella release GitHub di WinBoat"; exit 1; }
    mkdir -p "$HOME/.local/bin"
    curl -L --progress-bar -o "$APPIMAGE" "$url"
    chmod +x "$APPIMAGE"
    echo "Installato: $APPIMAGE"
fi

if [ ! -f "$DESKTOP" ]; then
    mkdir -p "$(dirname "$DESKTOP")"
    printf '[Desktop Entry]\nName=WinBoat\nExec=%s\nType=Application\nCategories=Utility;\nTerminal=false\n' "$APPIMAGE" > "$DESKTOP"
    echo "Creato: $DESKTOP"
fi

# Su btrfs disabilita il copy-on-write PRIMA che nascano i file della VM
# (efficace solo sui file creati dopo; innocuo altrove).
mkdir -p "$HOME/.winboat"
chattr +C "$HOME/.winboat" 2>/dev/null || true

# --- VM Windows -----------------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -qx WinBoat; then
    echo "VM Windows (container WinBoat): presente"
else
    cat <<'EOF'

AZIONE MANUALE RICHIESTA
------------------------
La VM Windows non esiste ancora. La prima installazione è guidata:
  1. Avvia WinBoat (icona nel menu, o ~/.local/bin/WinBoat.AppImage)
  2. Completa il wizard: Windows 11 Pro (obbligatorio: fa da host RDP),
     lingua, RAM >= 4 GB (6 consigliati), disco 64 GB (sparse)
  3. Attendi il termine dell'installazione automatica (20-45 min)
  4. Riesegui questo kit: ./setup-all.sh
EOF
    exit 2
fi

echo "Fase 1 completata."
