# Copies the mod into Transport Fever 3.
#   -Target Staging (default): the staging area ("My Mods" in the Mod Hub), used for validating and publishing
#   -Target Mods: the user mod folder (local\mods)
# Only the files the game needs are copied; development files (tools, tealdef, tlconfig, README) stay in the project.
# The mod.io file id written by the game after the first upload is kept and copied back into the project.
# Usage: powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 [-Target Staging|Mods] [-Remove]
param(
    [ValidateSet("Staging", "Mods")]
    [string]$Target = "Staging",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$modId = "parcel_delivery"
$folder = if ($Target -eq "Staging") { "staging_area" } else { "mods" }

$steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
$candidates = Get-ChildItem (Join-Path $steam "userdata") -Directory |
    ForEach-Object { Join-Path $_.FullName "3493540\local\$folder" } |
    Where-Object { Test-Path $_ }
if (-not $candidates) { throw "No Transport Fever 3 $folder folder found" }
$destination = Join-Path @($candidates)[0] $modId

if ($Remove) {
    if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
    Write-Output "Removed $destination"
    return
}

# keep the mod.io file id (written by the game after the first upload) in the project
$fileId = Join-Path $destination "_metadata\mod.io_fileid.txt"
if (Test-Path $fileId) {
    Copy-Item $fileId (Join-Path $project "_metadata\mod.io_fileid.txt") -Force
}

# update the file list of the content folder
$contentDir = Join-Path $project "content"
$files = Get-ChildItem $contentDir -Recurse -File |
    ForEach-Object { $_.FullName.Substring($contentDir.Length + 1).Replace("\", "/") } |
    Sort-Object
$json = [ordered]@{ archives = $null; files = @($files) } | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText((Join-Path $project "_content.json"), $json, (New-Object System.Text.UTF8Encoding $false))

# fresh copy of the runtime files, made beside the mod folder and moved in at once: a running game watches the staging
# area, and a half-copied folder without _metadata\modinfo.json makes it fall back to mod.json, which has no title (the
# mod then shows as "parcel_delivery (parcel_delivery)")
$temporary = "$destination.deploy"
if (Test-Path $temporary) { Remove-Item $temporary -Recurse -Force }
New-Item -ItemType Directory -Path $temporary | Out-Null
foreach ($item in "_metadata", "mod.json", "strings.json", "_content.json", "content") {
    Copy-Item (Join-Path $project $item) -Destination $temporary -Recurse
}if (Test-Path $destination) { Remove-Item $destination -Recurse -Force }
Move-Item $temporary $destination
Write-Output "Installed $project -> $destination"
