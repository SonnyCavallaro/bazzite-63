# bazzite-63: the per-user PowerShell environment, copied from /etc/skel into every new home
# (and into an older one by bazzite-mx's copy-paste hook) and read by pwsh at start. pwsh
# reads this profile and never /etc/profile.d, so Homebrew and mise are wired here; each
# block does nothing until pwsh is installed from Homebrew (`brew install powershell`).

# Homebrew: pwsh itself and the command-line tools installed with brew.
if (Test-Path '/home/linuxbrew/.linuxbrew/bin' -PathType Container) {
    if (($env:PATH -split ':') -notcontains '/home/linuxbrew/.linuxbrew/bin') {
        # Last, as /etc/profile.d/brew.sh puts it: mise's runtimes and the system win.
        $env:PATH = $env:PATH + ':/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin'
    }
}

# mise: the runtimes on PATH per prompt, the role /etc/profile.d/mise.sh has for bash.
if (Get-Command mise -ErrorAction SilentlyContinue) {
    # Homebrew's pwsh launcher exports its dotnet as DOTNET_ROOT, where mise would install.
    if ($env:DOTNET_ROOT -eq '/home/linuxbrew/.linuxbrew/opt/dotnet/libexec') {
        Remove-Item Env:DOTNET_ROOT
    }

    mise activate pwsh | Out-String | Invoke-Expression
}

# Windows-style Ctrl+C / Ctrl+V. PSReadLine's built-in clipboard functions need xclip on
# Linux; these handlers use wl-clipboard, which the base ships.
if ((Get-Module PSReadLine) -and (Get-Command wl-copy, wl-paste -ErrorAction SilentlyContinue)) {
    # Copy the PSReadLine selection (Shift+arrows) when there is one, else
    # cancel the current line: the CopyOrCancelLine semantics of Windows.
    Set-PSReadLineKeyHandler -Chord Ctrl+c -BriefDescription CopyOrCancelLine -ScriptBlock {
        $start = 0
        $length = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$start, [ref]$length)

        if ($start -ge 0) {
            $line = ''
            $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            # wl-copy forks a daemon that inherits a redirected stdout/stderr
            # and would hold the PowerShell pipeline open: redirect stdin only,
            # so the daemon detaches and the handler returns at once.
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
