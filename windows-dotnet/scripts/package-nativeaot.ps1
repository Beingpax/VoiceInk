$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $projectRoot 'artifacts'
$releaseDir = Join-Path (Split-Path -Parent $projectRoot) 'release/windows'
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
# Use a fresh directory so a package can never include stale publish files.
$packageName = 'VoiceInk-NativeAOT-win-x64-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$publishDir = Join-Path $artifacts $packageName
$archive = $publishDir + '.zip'
dotnet publish (Join-Path $projectRoot 'src/VoiceInk.App') -p:PublishProfile=NativeAOT -p:Platform=x64 -o $publishDir
if ($LASTEXITCODE -ne 0) { throw 'NativeAOT publish failed; no archive was created.' }
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $archive
$releaseArchive = Join-Path $releaseDir ([System.IO.Path]::GetFileName($archive))
Copy-Item -LiteralPath $archive -Destination $releaseArchive
Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256
Write-Output "Package: $archive"
Write-Output "Release package: $releaseArchive"
