# winboat-office-kit

Porta una macchina Bazzite/Fedora Atomic da zero a: **suite Office 365 e Teams
in una VM Windows gestita da WinBoat, con Outlook, Word, Excel e Teams nella
barra delle applicazioni di KDE Plasma come app native** (finestre singole
RemoteApp, icone originali).

## Uso

```bash
cd ~/Download/winboat-office-kit
./setup-all.sh
```

Ogni fase è **idempotente**: rieseguire l'intero kit su una macchina già
configurata non produce effetti collaterali. Le fasi sono anche eseguibili
singolarmente (`./01-...`, `./02-...`, `./03-...`).

## Le tre fasi

| Script | Cosa fa | Quando si ferma |
|---|---|---|
| `01-install-winboat.sh` | Verifica i prerequisiti (docker attivo, gruppo docker, `/dev/kvm`, xfreerdp) e installa l'AppImage di WinBoat (ultima release GitHub) in `~/.local/bin` con relativo `.desktop`. Pre-crea `~/.winboat` con `chattr +C` (niente copy-on-write btrfs sui file VM). | Esce con codice 2 se la **VM Windows non esiste ancora**: la prima installazione di Windows passa dal wizard grafico di WinBoat (interattivo per design). Completato il wizard, rieseguire il kit. |
| `02-install-office-vm.sh` | Accende la VM se spenta, attende il Guest API, e installa **dentro Windows** ciò che manca via `winget` (`--source winget`: la sorgente msstore dentro la VM fallisce con errore certificato) lanciato come RemoteApp PowerShell: `Microsoft.Office` (Microsoft 365 Apps) e `Microsoft.Teams`. Per Office il controllo "già installato?" interroga il Guest API (`/apps`); per Teams il Guest API è cieco (vedi sotto) e si sfrutta l'idempotenza di winget. | Attende fino a 40 min la comparsa di Word e fino a 15 min la fine del winget di Teams. |
| `03-create-taskbar-launchers.sh` | Dal Guest API estrae **icone originali** e coordinate di lancio delle app; genera `~/.local/bin/winboat-app` (il lanciatore comune), 4 file `.desktop` e aggiunge le voci mancanti alla task bar di Plasma (con backup della config e riavvio di plasmashell solo se modificata). Per Teams — che il Guest API non enumera — usa le coordinate MSIX standard (`explorer.exe shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams`) e l'icona fornita dal kit (`resources/teams.png`, estratta dagli asset originali del pacchetto). | Esce con codice 3 se una delle app senza fallback non risulta nella VM (fase 2 incompleta). |

## Requisiti della macchina

- Immagine Bazzite/Fedora Atomic **con Docker integrato** e servizio attivo
  (`sudo systemctl enable --now docker`), utente nel gruppo `docker`.
- Virtualizzazione KVM abilitata (`/dev/kvm` presente).
- `xfreerdp` (FreeRDP), `python3`, `curl` — presenti di serie su Bazzite.
- KDE Plasma (la fase 3 modifica la task bar `icontasks` di Plasma).
- Sessione desktop attiva: la fase 2 apre finestre RemoteApp temporanee
  (console PowerShell dell'installazione).

## Punti manuali (non automatizzabili)

1. **Primo wizard WinBoat** (solo su macchina nuova): scegliere **Windows 11
   Pro** (obbligatorio: l'edizione Pro fa da host RDP per il RemoteApp),
   RAM ≥ 4 GB (6 consigliati), disco 64 GB sparse.
2. **Attivazione Office**: al primo avvio di Word/Excel/Outlook fare il login
   con l'account Microsoft 365. `winget` installa, non attiva.

## Architettura del lancio (per capire cosa si sta toccando)

- WinBoat gestisce **una sola VM Windows** in un container Docker
  (`dockur/windows`, container chiamato `WinBoat`). Le app girano tutte lì
  dentro, nella stessa sessione utente.
- Ogni icona in barra esegue `~/.local/bin/winboat-app <chiave>`
  (`outlook|word|excel|teams`): lo script legge **a runtime** credenziali
  (da `~/.winboat/docker-compose.yml`) e porta RDP (da `docker port WinBoat
  3389/tcp` — la porta può cambiare a ogni avvio del container, per questo
  non è cablata) e apre la singola app via `xfreerdp` in modalità RemoteApp.
- Le app classiche (.EXE) si lanciano col percorso diretto; le app UWP/MSIX
  come Teams passano da `explorer.exe` + `shell:AppsFolder\<PackageFamily>!<AppId>`
  (è il Guest API a fornire la forma giusta, lo script la eredita).
- `StartupWMClass` di ogni `.desktop` coincide con il `/wm-class` passato a
  FreeRDP: le finestre aperte si raggruppano sulla propria icona in barra.
- Il Guest API di WinBoat risponde su `docker port WinBoat 7148/tcp`
  (`/health`, `/apps` — quest'ultimo include le icone base64 delle app).

## File generati/modificati sulla macchina

| Percorso | Ruolo |
|---|---|
| `~/.local/bin/WinBoat.AppImage` + `~/.local/share/applications/winboat.desktop` | WinBoat |
| `~/.winboat/` | Config e compose della VM (di WinBoat; il kit lo pre-crea solo per il `chattr +C`) |
| `~/.local/bin/winboat-app` | Lanciatore comune (rigenerato dalla fase 3) |
| `~/.local/share/applications/winboat-{outlook,word,excel,teams}.desktop` | Voci di menu/barra |
| `~/.local/share/icons/hicolor/32x32/apps/winboat-*.png` | Icone originali |
| `~/.config/plasma-org.kde.plasma.desktop-appletsrc` | Task bar (backup in `*.bak-winboat-kit` alla prima modifica) |

## Limiti noti

- Il Guest API di WinBoat (fino alla 0.9) **non enumera il nuovo Teams
  unificato** (pacchetto MSIX `MSTeams_8wekyb3d8bbwe`), pur elencando le altre
  app UWP: Teams non compare nella lista app di WinBoat né in `/apps`. Il kit
  aggira il limite con coordinate di lancio cablate e icona a corredo.
- La sorgente `msstore` di winget dentro la VM fallisce
  (`0x8a15005e`, certificato non corrispondente): ogni install va fatta con
  `--source winget`.

- Dopo un riavvio della macchina il container `WinBoat` non riparte da solo
  (`restart: on-failure`): aprire WinBoat, che avvia la VM. Le icone in barra
  notificano "VM non in esecuzione" se cliccate a VM spenta.
- La fase 3 individua la task bar come la riga `launchers=` più lunga della
  config Plasma: con layout multi-pannello esotici verificare l'esito.
- `winget Microsoft.Office` installa Microsoft 365 Apps in italiano solo se
  la VM è localizzata it-IT (il wizard WinBoat con lingua Italiano lo fa).
