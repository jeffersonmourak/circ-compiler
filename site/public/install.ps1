# circ-compile installer for Windows (PowerShell).
#
#   irm https://circ-lang.org/install.ps1 | iex
#
# Downloads a prebuilt circ-compile.exe from the project's GitHub Releases
# (published automatically for each version tag by the CLI release workflow)
# and installs it. Environment overrides:
#   $env:CIRC_VERSION       version/tag to install, e.g. 0.0.2 or v0.0.2
#                           (default: the latest published release)
#   $env:CIRC_INSTALL_DIR   install directory (default: %LOCALAPPDATA%\circ\bin)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo       = 'https://github.com/jeffersonmourak/circ-compiler'
$Api        = 'https://api.github.com/repos/jeffersonmourak/circ-compiler'
$Label      = 'windows-x86_64'   # the only Windows build; runs under emulation on ARM64
$InstallDir = if ($env:CIRC_INSTALL_DIR) { $env:CIRC_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'circ\bin' }

function Say($m) { Write-Host "circ-install: $m" }
function Die($m) { throw "circ-install: $m" }

# Resolve the tag: explicit override (accept 0.0.2 or v0.0.2), else the latest
# published release via the GitHub API (Invoke-RestMethod sends a User-Agent and
# parses the JSON, so tag_name is read directly).
$Tag = $env:CIRC_VERSION
if ($Tag) {
  if ($Tag -notmatch '^v') { $Tag = "v$Tag" }
} else {
  try { $Tag = (Invoke-RestMethod -Uri "$Api/releases/latest").tag_name } catch { }
}
if (-not $Tag) { Die "could not determine the latest release; set `$env:CIRC_VERSION (see $Repo)" }

$Asset = "circ-compile-$Tag-$Label.exe"
$Url   = "$Repo/releases/download/$Tag/$Asset"
Say "installing circ-compile $Tag ($Label)"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("circ-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
  $TmpExe = Join-Path $Tmp 'circ-compile.exe'
  try { Invoke-WebRequest -Uri $Url -OutFile $TmpExe } catch { Die "download failed: $Url" }
  if (-not (Test-Path $TmpExe) -or (Get-Item $TmpExe).Length -eq 0) { Die "downloaded an empty file from $Url" }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item -Path $TmpExe -Destination (Join-Path $InstallDir 'circ-compile.exe') -Force
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
