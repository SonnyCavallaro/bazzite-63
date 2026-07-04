# Per-user PowerShell environment (CurrentUserAllHosts). pwsh reads this
# profile, never /etc/profile.d, so brew and mise get wired here: without it
# the default Konsole shell would see none of the per-user dev tooling.
# Each block is a no-op until `ujust setup-dev` has installed the tools.

# Homebrew (per-user CLI tools: pwsh itself, sqlcmd, mise)
if (Test-Path '/home/linuxbrew/.linuxbrew/bin' -PathType Container) {
    if (($env:PATH -split ':') -notcontains '/home/linuxbrew/.linuxbrew/bin') {
        $env:PATH = '/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:' + $env:PATH
    }
}

# mise runtimes (node, python, java, dotnet) — per-prompt activation hook,
# same role as `mise activate bash` in /etc/profile.d/99-mise.sh
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Out-String | Invoke-Expression
}
