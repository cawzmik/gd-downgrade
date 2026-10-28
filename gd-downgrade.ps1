param([switch]$Undo, [string]$Manifest = "")

# Rolls Steam Geometry Dash back to 2.2081 so Geode mods keep working until
# Geode supports 2.209. Run with -Undo to go back to the newest version.

$DefaultManifest = "3816559102876907245"
$AppId = 322170
$DepotId = 322171

$ErrorActionPreference = "Stop"

function Say($text, $color = "White") { Write-Host $text -ForegroundColor $color }
function Done($code) {
    Write-Host ""
    Read-Host "Press Enter to close" | Out-Null
    exit $code
}

function Find-Steam {
    $path = $null
    try { $path = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath).SteamPath } catch { }
    if (-not $path) { $path = Join-Path ${env:ProgramFiles(x86)} "Steam" }
    return ($path -replace "/", "\")
}

function Find-Library($steam) {
    $libs = @($steam)
    $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        foreach ($m in (Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"')) {
            $libs += ($m.Matches[0].Groups[1].Value -replace '\\\\', '\')
        }
    }
    foreach ($lib in $libs) {
        if (Test-Path (Join-Path $lib "steamapps\appmanifest_$AppId.acf")) { return $lib }
    }
    return $null
}

function Can-Write($dir) {
    try {
        $f = Join-Path $dir ".gd-downgrade-test"
        [IO.File]::WriteAllText($f, "x")
        Remove-Item $f -Force
        return $true
    } catch { return $false }
}

$ShortcutName = "Geometry Dash 2.2081.lnk"
function Shortcut-Path { return (Join-Path ([Environment]::GetFolderPath("Desktop")) $ShortcutName) }

function Make-Shortcut($gd) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut((Shortcut-Path))
        $lnk.TargetPath = Join-Path $gd "GeometryDash.exe"
        $lnk.WorkingDirectory = $gd
        $lnk.Save()
        return $true
    } catch { return $false }
}

function Wait-GDClosed {
    while (Get-Process -Name "GeometryDash" -ErrorAction SilentlyContinue) {
        Say "Geometry Dash is open. Close it, then press Enter." Yellow
        Read-Host | Out-Null
    }
}

$script:logPos = 0
function Read-NewLog($log) {
    if (-not (Test-Path $log)) { return "" }
    $fs = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($fs.Length -lt $script:logPos) { $script:logPos = 0 }
        [void]$fs.Seek($script:logPos, [IO.SeekOrigin]::Begin)
        $reader = New-Object IO.StreamReader($fs)
        $text = $reader.ReadToEnd()
        $script:logPos = $fs.Length
        return $text
    } finally { $fs.Dispose() }
}

function Folder-Size($dir) {
    if (-not (Test-Path $dir)) { return 0 }
    $sum = (Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($sum) { return [int64]$sum } else { return 0 }
}

function Any-Locked($dir) {
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        try {
            $fs = [IO.File]::Open($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            $fs.Dispose()
        } catch { return $true }
    }
    return $false
}

function Copy-Depot($from, $to) {
    $root = (Get-Item -LiteralPath $from).FullName.TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    $i = 0
    foreach ($f in $files) {
        $i++
        $rel = $f.FullName.Substring($root.Length).TrimStart('\')
        $dest = Join-Path $to $rel
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tries = 0
        while ($true) {
            try {
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                break
            } catch {
                $tries++
                if ($tries -ge 30) { throw }
                Start-Sleep -Seconds 2
            }
        }
        if (($i % 20) -eq 0 -or $i -eq $files.Count) { Write-Host -NoNewline ("`r     Copied {0} of {1} files   " -f $i, $files.Count) }
    }
    Write-Host ""
}

try {
    $steam = Find-Steam
    $lib = Find-Library $steam
    if (-not $lib) {
        Say "Couldn't find Geometry Dash in your Steam library. This only works for the Steam version." Red
        Done 1
    }
    $acf = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
    $gd = Join-Path $lib "steamapps\common\Geometry Dash"

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin -and -not ((Can-Write $gd) -and (Can-Write (Join-Path $steam "steamapps")))) {
        Say "Asking for permission to change the Geometry Dash folder..." Yellow
        $relaunch = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($Undo) { $relaunch += " -Undo" }
        if ($Manifest) { $relaunch += " -Manifest $Manifest" }
        Start-Process powershell -Verb RunAs -ArgumentList $relaunch
        exit 0
    }

    if ($Undo) {
        Say "Putting Geometry Dash back on the newest version" Cyan
        Say ""
        Wait-GDClosed
        Set-ItemProperty -Path $acf -Name IsReadOnly -Value $false
        Remove-Item -Path (Shortcut-Path) -Force -ErrorAction SilentlyContinue
        Start-Process "steam://validate/$AppId"
        Say "Done. Steam is checking the game files now and will update GD to the newest version." Green
        Say "Only do this once Geode supports the new version, or your mods won't load."
        Done 0
    }

    Say "GD Downgrade: rolls Geometry Dash back to 2.2081 so Geode mods work again" Cyan
    Say ""
    Say "Found GD in: $gd"
    Say "Your save gets backed up first (to your user folder)."
    Say ""
    Read-Host "Press Enter to start" | Out-Null

    if (-not $Manifest) { $Manifest = $DefaultManifest }
    while ($Manifest -notmatch '^\d{10,25}$') {
        $Manifest = (Read-Host "Paste the 2.2081 manifest ID").Trim()
    }

    Wait-GDClosed

    $save = Join-Path $env:LOCALAPPDATA "GeometryDash"
    $files = @()
    if (Test-Path $save) { $files = @(Get-ChildItem -Path $save -File -Filter "*.dat") }
    if ($files.Count -gt 0) {
        $name = "GD save backup " + (Get-Date -Format "yyyy-MM-dd HH-mm")
        $backup = $null
        foreach ($root in @($env:USERPROFILE, $PSScriptRoot, $env:TEMP)) {
            if (-not $root) { continue }
            $dest = Join-Path $root $name
            try {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                foreach ($f in $files) { Copy-Item -Path $f.FullName -Destination $dest -Force }
                $backup = $dest
                break
            } catch {
                Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($backup) {
            Say "1/4  Backed up your save to: $backup"
        } else {
            Say "1/4  Couldn't back up your save anywhere." Yellow
            $go = Read-Host "Type yes to keep going without a backup, or just press Enter to stop"
            if ($go.Trim().ToLower() -ne "yes") { Done 1 }
        }
    } else {
        Say "1/4  No save files found, skipping the backup" Yellow
    }

    $depot = Join-Path $steam "steamapps\content\app_$AppId\depot_$DepotId"
    if (Test-Path $depot) { Remove-Item -Path $depot -Recurse -Force }
    $log = Join-Path $steam "logs\content_log.txt"
    if (Test-Path $log) { $script:logPos = (Get-Item $log).Length }

    while (-not (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
        Say "Steam isn't open. Open Steam, log in, then press Enter." Yellow
        Read-Host | Out-Null
    }

    $command = "download_depot $AppId $DepotId $Manifest"
    Set-Clipboard -Value $command
    # Through Explorer so it works even when this window has admin rights and Steam doesn't
    try { Start-Process -FilePath "explorer.exe" -ArgumentList "steam://open/console" } catch { Start-Process "steam://open/console" }
    Say ""
    Say "2/4  Steam's console should open now. Click the box at the bottom of it," Yellow
    Say "     press Ctrl+V and then Enter. (It pastes: $command)" Yellow
    Say "     Then come back here and wait. Don't close this window." Yellow
    Say ""
    Say "     If the console didn't open: press Windows+R, type steam://open/console" Yellow
    Say "     and press Enter. Then click Steam's console box, Ctrl+V, Enter." Yellow
    Say ""

    $seen = ""
    $lastSize = -1
    $stableSince = $null
    $readySince = $null
    $waitedMsg = $false
    $deadline = (Get-Date).AddMinutes(45)
    while ($true) {
        Start-Sleep -Seconds 2
        $seen += Read-NewLog $log
        if ($seen -match "Depot download failed[^\r\n]*") {
            Say ""
            Say "Steam couldn't download it: $($Matches[0])" Red
            Say "Check that the manifest ID is right and that you own GD on this Steam account." Red
            Done 1
        }
        $size = Folder-Size $depot
        if ($size -gt 0) { Write-Host -NoNewline ("`r     Downloading... {0:N0} MB   " -f ($size / 1MB)) }
        $complete = $seen -match "Depot download complete[^\r\n]*depot_$DepotId"
        if ($size -gt 0 -and $size -eq $lastSize -and (Test-Path (Join-Path $depot "GeometryDash.exe"))) {
            if (-not $stableSince) { $stableSince = Get-Date }
        } else { $stableSince = $null }
        $lastSize = $size
        if ($complete -or ($stableSince -and ((Get-Date) - $stableSince).TotalSeconds -ge 30)) {
            if (-not $readySince) { $readySince = Get-Date }
            if (-not (Any-Locked $depot)) { break }
            if (((Get-Date) - $readySince).TotalSeconds -ge 180) { break }
            if (-not $waitedMsg) {
                Write-Host ""
                Say "     Steam is still writing files. Waiting for it to finish..." Yellow
                $waitedMsg = $true
            }
        } else { $readySince = $null }
        if ((Get-Date) -gt $deadline) {
            Say ""
            Say "This is taking too long. Make sure you pasted the command into Steam's console and pressed Enter, then run this again." Red
            Done 1
        }
    }
    Write-Host ""

    Wait-GDClosed
    Say "3/4  Copying the 2.2081 files into your GD folder"
    Copy-Depot $depot $gd

    Say "4/4  Stopping Steam from updating GD again"
    Set-ItemProperty -Path $acf -Name IsReadOnly -Value $true
    Remove-Item -Path $depot -Recurse -Force -ErrorAction SilentlyContinue

    $made = Make-Shortcut $gd
    Say ""
    Say "Done! Geometry Dash is on 2.2081 and your mods will work." Green
    Say ""
    Say "IMPORTANT: Steam's Play button won't work now (it tries to update and fails)." Yellow
    if ($made) {
        Say "Open GD with the 'Geometry Dash 2.2081' shortcut on your Desktop instead. Keep Steam open." Yellow
    } else {
        Say "Open GeometryDash.exe in your GD folder instead, and keep Steam open:" Yellow
        Say "  $gd" Yellow
    }
    Say ""
    Say "When Geode supports the new GD version, run 'Undo GD downgrade.bat' to update again."
    Done 0
} catch {
    Say ""
    Say "Something went wrong: $($_.Exception.Message)" Red
    if ($_.Exception.Message -match "being used by another process") {
        Say "A file was still in use by Steam or your antivirus. Wait a minute, then run this again." Yellow
    }
    Say "Nothing in your save was deleted. Send a screenshot of this window to cawzmik." Red
    Done 1
}
