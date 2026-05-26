# circ-compile installer for Windows (PowerShell).
#
#   irm https://circ-lang.org/install.ps1 | iex
#
# Downloads a prebuilt circ-compile.exe from https://circ-lang.org/downloads
# and installs it. Environment overrides:
#   $env:CIRC_VERSION       version to install (default: the latest published)
#   $env:CIRC_INSTALL_DIR   install directory (default: %LOCALAPPDATA%\circ\bin)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Downloads  = 'https://circ-lang.org/downloads'
$Repo       = 'https://github.com/jeffersonmourak/circ-compiler'
$Label      = 'windows-x86_64'   # the only Windows build; runs under emulation on ARM64
$InstallDir = if ($env:CIRC_INSTALL_DIR) { $env:CIRC_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'circ\bin' }

function Say($m) { Write-Host "circ-install: $m" }
function Die($m) { throw "circ-install: $m" }

# Resolve the version: explicit override, else the published "latest" pointer
# (written next to the archives by tools/build-dist.sh).
$Version = $env:CIRC_VERSION
if (-not $Version) {
  try { $Version = (Invoke-RestMethod -Uri "$Downloads/latest").ToString().Trim() } catch { }
}
if (-not $Version) { Die "could not determine the latest version; set `$env:CIRC_VERSION (see $Repo)" }

$Pkg = "circ-compile-$Version-$Label"
$Url = "$Downloads/$Pkg.zip"
Say "installing circ-compile $Version ($Label)"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("circ-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
  $Zip = Join-Path $Tmp 'pkg.zip'
  try { Invoke-WebRequest -Uri $Url -OutFile $Zip } catch { Die "download failed: $Url" }
  Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
  $Exe = Join-Path $Tmp (Join-Path $Pkg 'circ-compile.exe')
  if (-not (Test-Path $Exe)) { Die "archive did not contain circ-compile.exe" }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item -Path $Exe -Destination (Join-Path $InstallDir 'circ-compile.exe') -Force
} finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Say "installed to $(Join-Path $InstallDir 'circ-compile.exe')"

# Add the install dir to the user PATH if it is not already there.
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $UserPath) { $UserPath = '' }
if (($UserPath -split ';') -notcontains $InstallDir) {
  [Environment]::SetEnvironmentVariable('Path', ($UserPath.TrimEnd(';') + ';' + $InstallDir).TrimStart(';'), 'User')
  Say "added $InstallDir to your user PATH; open a new terminal, then run: circ-compile --help"
} else {
  Say "ready: run 'circ-compile --help'"
}
