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

# Windows-PowerShell-style Ctrl+C / Ctrl+V, scoped to pwsh only (Konsole
# shortcuts are app-wide, so bash keeps its defaults). PSReadLine's built-in
# clipboard functions need xclip on Linux, hence custom wl-clipboard handlers.
if ((Get-Module PSReadLine) -and (Get-Command wl-copy, wl-paste -ErrorAction SilentlyContinue)) {
    # Copy the PSReadLine selection (Shift+arrows) if there is one, else
    # cancel the current line — same semantics as CopyOrCancelLine on Windows.
    Set-PSReadLineKeyHandler -Chord Ctrl+c -BriefDescription CopyOrCancelLine -ScriptBlock {
        $start = 0; $length = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$start, [ref]$length)
        if ($start -ge 0) {
            $line = ''; $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            # wl-copy forks a daemon that inherits any redirected stdout/stderr
            # and holds a PowerShell pipeline open forever — redirect stdin only
            # so the daemon detaches and the handler returns immediately.
            $psi = [System.Diagnostics.ProcessStartInfo]::new('wl-copy')
            $psi.ArgumentList.Add('--trim-newline')
            $psi.RedirectStandardInput = $true
            $psi.UseShellExecute = $false
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.StandardInput.Write($line.Substring($start, $length))
            $p.StandardInput.Close()
            $p.WaitForExit()
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine()
        }
    }

    Set-PSReadLineKeyHandler -Chord Ctrl+v -BriefDescription Paste -ScriptBlock {
        $text = (wl-paste --no-newline 2>$null) -join "`n"
        if ($text) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($text)
        }
    }
}
