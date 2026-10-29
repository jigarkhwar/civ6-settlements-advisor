# Collects what a Settlements Advisor bug report needs into one zip on Windows: the game's
# logs (Lua.log carries the mod's output), the newest saves, crash reports, system and mod
# versions. Needs nothing but Windows PowerShell 5.1; does not need the git repository.
#
# Run: double-click collect_diagnostics.cmd next to this file, or
#   powershell -NoProfile -ExecutionPolicy Bypass -File collect_diagnostics.ps1 [-Saves 2]
# Output: SA-diagnostics-yyyyMMdd-HHmmss.zip on the Desktop. Attach it to the issue.
# Lua.log is rewritten at every game start: collect before starting the game again.
# Kept ASCII-only: PowerShell 5.1 reads a file without BOM in the ANSI code page.

param([int]$Saves = 2)
$ErrorActionPreference = 'Continue'

$docs = [Environment]::GetFolderPath('MyDocuments')   # follows OneDrive redirection
$game = Join-Path $docs "My Games\Sid Meier's Civilization VI"
$logs = Join-Path $game 'Logs'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $env:TEMP "SA-diagnostics-$stamp"
$zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "SA-diagnostics-$stamp.zip"
$since = (Get-Date).AddDays(-2)
$maxCopy = 50MB
foreach ($d in 'game-logs', 'saves', 'crashes', 'mods') { New-Item -ItemType Directory -Force -Path (Join-Path $out $d) | Out-Null }

function Note($text) { Add-Content -Path (Join-Path $out 'info.txt') -Value $text -Encoding UTF8 }

if (-not (Test-Path $game)) { Write-Host "Game folder not found: $game" -ForegroundColor Red }

# 1. The game's logs. Lua.log holds every print of the mod (lines "SA_Main: SA_...").
Get-ChildItem -Path $logs -File -ErrorAction SilentlyContinue |
  Where-Object { ($_.Extension -in '.log', '.csv') -and $_.Length -lt $maxCopy } |
  Copy-Item -Destination (Join-Path $out 'game-logs')
$lua = Join-Path $logs 'Lua.log'
if (Test-Path $lua) {
  Select-String -Path $lua -Pattern 'SA_(ERROR|SLOW|READY|DMT|PINS|PLAZA|MISMATCH)' |
    Select-Object -Last 300 | ForEach-Object { $_.Line } |
    Out-File -FilePath (Join-Path $out 'lua-SA-lines.txt') -Encoding UTF8
} else {
  'Lua.log not found: set "EnableTuner 1" in AppOptions.txt, start the game again and repeat the bug.' |
    Out-File -FilePath (Join-Path $out 'lua-MISSING.txt') -Encoding UTF8
}

# 2. The newest saves (quick, auto and manual).
Get-ChildItem -Path (Join-Path $game 'Saves') -Recurse -File -Filter '*.Civ6Save' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First $Saves |
  Copy-Item -Destination (Join-Path $out 'saves')

# 3. Crashes of the last two days: Windows Error Reporting files, local dumps, event log.
$crashDir = Join-Path $out 'crashes'
foreach ($wer in "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive", "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue",
                 "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue") {
  Get-ChildItem -Path $wer -Directory -Filter '*Civilization*' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $since } | ForEach-Object {
      $target = Join-Path $crashDir $_.Name
      New-Item -ItemType Directory -Force -Path $target | Out-Null
      Get-ChildItem -Path $_.FullName -File | Where-Object { $_.Length -lt $maxCopy } | Copy-Item -Destination $target
    }
}
Get-ChildItem -Path "$env:LOCALAPPDATA\CrashDumps" -File -Filter 'Civilization*' -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -gt $since } | ForEach-Object {
    if ($_.Length -lt $maxCopy) { Copy-Item $_.FullName -Destination $crashDir }
    else { Note ("crash dump too large to attach: {0} ({1:N0} MB)" -f $_.FullName, ($_.Length / 1MB)) }
  }
try {
  Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since } -ErrorAction Stop |
    Where-Object { $_.Message -match 'Civilization' } |
    Select-Object TimeCreated, ProviderName, Id, Message | Format-List |
    Out-File -FilePath (Join-Path $crashDir 'application-events.txt') -Encoding UTF8 -Width 300
} catch { }

# 4. Versions: system, game settings, which mods are enabled and which files of the mod are installed.
Note "collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
try {
  $os = Get-CimInstance Win32_OperatingSystem
  Note "Windows: $($os.Caption) $($os.Version), RAM $([math]::Round($os.TotalVisibleMemorySize / 1MB)) GB"
  Get-CimInstance Win32_VideoController | ForEach-Object { Note "GPU: $($_.Name), driver $($_.DriverVersion)" }
} catch { }
$running = Get-Process -Name 'CivilizationVI*' -ErrorAction SilentlyContinue
Note ("game running: " + $(if ($running) { ($running | ForEach-Object { $_.ProcessName }) -join ', ' } else { 'no' }))
$app = Join-Path $game 'AppOptions.txt'
if (Test-Path $app) {
  Note 'AppOptions:'
  Select-String -Path $app -Pattern '^(EnableTuner|RenderWidth|RenderHeight|FullScreen)' | ForEach-Object { Note ("  " + $_.Line) }
}
$modding = Join-Path $logs 'Modding.log'
if (Test-Path $modding) {
  Note 'mods in Modding.log:'
  Select-String -Path $modding -Pattern 'Detailed Map Tacks|Settlements Advisor' | Select-Object -Last 6 | ForEach-Object { Note ("  " + $_.Line) }
}

# The mod's installed files with short SHA-256: tells which version of the code is in the game.
$roots = @(Join-Path $game 'Mods')
try {
  $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
  if ($steam) { $roots += (Join-Path $steam 'steamapps\workshop\content\289070') }
} catch { }
foreach ($root in $roots) {
  Get-ChildItem -Path $root -Recurse -Depth 2 -File -Filter '*.modinfo' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'SettlementsAdvisor.modinfo' -or (Select-String -Path $_.FullName -Pattern 'Detailed Map Tacks' -Quiet) } |
    ForEach-Object {
      $dir = $_.DirectoryName
      Note "mod folder: $dir"
      Copy-Item $_.FullName -Destination (Join-Path $out 'mods')
      if ($_.Name -eq 'SettlementsAdvisor.modinfo') {
        Get-ChildItem -Path $dir -Recurse -File | ForEach-Object {
          $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
          "{0}  {1:yyyy-MM-dd HH:mm}  {2}" -f $hash, $_.LastWriteTime, $_.FullName.Substring($dir.Length + 1)
        } | Out-File -FilePath (Join-Path $out 'mods\SettlementsAdvisor-files.txt') -Encoding UTF8
      }
    }
}

Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Remove-Item -Recurse -Force $out
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Done: $zip ($size MB)" -ForegroundColor Green
if ($size -gt 25) { Write-Host 'GitHub accepts up to 25 MB: run again with -Saves 1.' -ForegroundColor Yellow }
