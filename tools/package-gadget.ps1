# Package the Najjar Pro gadget into an installable .vgadget (Windows).
# Usage:  powershell -ExecutionPolicy Bypass -File tools\package-gadget.ps1
# Output: gadget\release\NajjarPro.vgadget
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Gadget = Join-Path $Root "gadget"
$Out = Join-Path $Gadget "release"
$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ("najjar-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $Out | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "NajjarPro\src\najjar") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "NajjarPro\hardware") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "NajjarPro\lang") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "NajjarPro\importers") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "NajjarPro\toolpaths") | Out-Null

Copy-Item (Join-Path $Gadget "vcarve\*.lua") (Join-Path $Stage "NajjarPro")
Copy-Item (Join-Path $Gadget "src\najjar\*.lua") (Join-Path $Stage "NajjarPro\src\najjar")
Copy-Item (Join-Path $Gadget "hardware\*.json") (Join-Path $Stage "NajjarPro\hardware")
Copy-Item (Join-Path $Gadget "lang\*.json") (Join-Path $Stage "NajjarPro\lang")
Copy-Item (Join-Path $Gadget "importers\*.json") (Join-Path $Stage "NajjarPro\importers")
if (Test-Path (Join-Path $Gadget "toolpaths")) { Copy-Item (Join-Path $Gadget "toolpaths\*") (Join-Path $Stage "NajjarPro\toolpaths") }

$Vgadget = Join-Path $Out "NajjarPro.vgadget"
if (Test-Path $Vgadget) { Remove-Item $Vgadget }
Compress-Archive -Path (Join-Path $Stage "NajjarPro") -DestinationPath ($Vgadget + ".zip")
Rename-Item ($Vgadget + ".zip") "NajjarPro.vgadget"
Remove-Item -Recurse -Force $Stage

Write-Host "packaged: $Vgadget"
