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

    $command = "download_depot $AppId $DepotId $Manifest"
    Set-Clipboard -Value $command
    Start-Process "steam://open/console"
    Say ""
    Say "2/4  Steam's console just opened. Click the box at the bottom of it," Yellow
    Say "     press Ctrl+V and then Enter. (It pastes: $command)" Yellow
    Say "     Then come back here and wait. Don't close this window." Yellow
    Say ""

    $seen = ""
    $lastSize = -1
    $stableSince = $null
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
        if ($complete -or ($stableSince -and ((Get-Date) - $stableSince).TotalSeconds -ge 30)) { break }
        if ((Get-Date) -gt $deadline) {
            Say ""
            Say "This is taking too long. Make sure you pasted the command into Steam's console and pressed Enter, then run this again." Red
            Done 1
        }
    }
    Write-Host ""

    Wait-GDClosed
    Say "3/4  Copying the 2.2081 files into your GD folder"
    Copy-Item -Path (Join-Path $depot "*") -Destination $gd -Recurse -Force

    Say "4/4  Stopping Steam from updating GD again"
    Set-ItemProperty -Path $acf -Name IsReadOnly -Value $true
    Remove-Item -Path $depot -Recurse -Force -ErrorAction SilentlyContinue

    Say ""
    Say "Done! Geometry Dash is on 2.2081. Open it from Steam like normal and your mods will work." Green
    Say "If Steam says it needs an update, open GeometryDash.exe in the GD folder instead (keep Steam open)."
    Say "When Geode supports the new GD version, run 'Undo GD downgrade.bat' to update again."
    Done 0
} catch {
    Say ""
    Say "Something went wrong: $($_.Exception.Message)" Red
    Say "Nothing in your save was deleted. Send a screenshot of this window to cawzmik." Red
    Done 1
}
