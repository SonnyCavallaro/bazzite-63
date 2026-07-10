#!/usr/bin/env bash
# winboat-office-kit — orchestratore: esegue le tre fasi in ordine.
# Vedi README.md per il funzionamento e i punti manuali.
set -euo pipefail
cd "$(dirname "$0")"

./01-install-winboat.sh
./02-install-office-vm.sh
./03-create-taskbar-launchers.sh

echo
echo "Setup completato: Outlook, Word, Excel e Teams sono in barra."
echo "Ricorda: al primo avvio di una app Office serve il login Microsoft 365."
