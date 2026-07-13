[General]
Name=Powershell
# pwsh is the host's, in Homebrew (through `ujust setup-dev`): bash until it exists, so a
# host without it still opens a working terminal.
Command=/bin/bash -c 'p=/home/linuxbrew/.linuxbrew/bin/pwsh; [ -x "$p" ] && exec "$p"; exec bash -l'
StartInCurrentSessionDir=true
Parent=FALLBACK/
