[General]
Name=Powershell
# pwsh is per-user (brew, via `ujust setup-dev`): fall back to bash until it
# exists so a fresh install still gets a working terminal out of the box.
Command=/usr/bin/bash -c '[ -x /home/linuxbrew/.linuxbrew/bin/pwsh ] && exec /home/linuxbrew/.linuxbrew/bin/pwsh; exec bash -l'
StartInCurrentSessionDir=true
Parent=FALLBACK/
