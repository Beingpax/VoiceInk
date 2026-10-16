param(
    [ValidateSet('x64', 'arm64')]
    [string]$Architecture = 'x64'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$appProject = Join-Path $projectRoot 'src/VoiceInk.App/VoiceInk.App.csproj'
$artifacts = Join-Path $projectRoot 'artifacts'

# The <Version> in VoiceInk.App.csproj is the single source of truth (semantic versioning).
$version = ([xml](Get-Content -LiteralPath $appProject -Raw)).Project.PropertyGroup.Version |
    Where-Object { $_ } | Select-Object -First 1
$semver = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ($version -notmatch $semver) {
    throw "Version '$version' in $appProject is not a valid semantic version (MAJOR.MINOR.PATCH)."
}

$platform = $Architecture
$runtime = "win-$Architecture"
$tag = "v$version"
$releaseDir = Join-Path (Split-Path -Parent $projectRoot) "release/windows/$tag"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

# Use a fresh directory so a package can never include stale publish files.
$publishDir = Join-Path $artifacts ("VoiceInk-NativeAOT-$runtime-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
dotnet publish $appProject -p:PublishProfile=NativeAOT -p:Platform=$platform -p:RuntimeIdentifier=$runtime -o $publishDir
if ($LASTEXITCODE -ne 0) { throw 'NativeAOT publish failed; no archive was created.' }

$releaseArchive = Join-Path $releaseDir "VoiceInk-$Architecture-$version.zip"
Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $releaseArchive -Force
Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256
Write-Output "Version: $version"
Write-Output "Release package: $releaseArchive"
