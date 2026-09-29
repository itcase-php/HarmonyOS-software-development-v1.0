param([string]$HapPath = (Join-Path $PSScriptRoot '../entry/build/default/outputs/default/entry-default-unsigned.hap'))
$ErrorActionPreference = 'Stop'
$taskProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskHapPath = (Resolve-Path -LiteralPath $HapPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskArchive = [System.IO.Compression.ZipFile]::OpenRead($taskHapPath)
try {
  $taskRequiredEntries = @('libs/arm64-v8a/libentry.so', 'libs/x86_64/libentry.so',
    'ets/modules.abc', 'resources/rawfile/format-registry/formats.json',
    'resources/rawfile/format-registry/conversion-matrix.json',
    'resources/rawfile/format-registry/manifest.json')
  $taskEvidence = @()
  foreach ($taskName in $taskRequiredEntries) {
    $taskEntry = $taskArchive.GetEntry($taskName)
    if ($null -eq $taskEntry -or $taskEntry.Length -le 0) { throw "Missing/empty HAP entry: $taskName" }
    $taskStream = $taskEntry.Open()
    $taskHasher = [System.Security.Cryptography.SHA256]::Create()
    try { $taskDigest = [System.BitConverter]::ToString($taskHasher.ComputeHash($taskStream)).Replace('-', '').ToLowerInvariant() }
    finally { $taskStream.Dispose(); $taskHasher.Dispose() }
    if ($taskName.StartsWith('resources/rawfile/format-registry/')) {
      $taskFileName = [System.IO.Path]::GetFileName($taskName)
      $taskSourcePath = Join-Path $taskProjectRoot "entry/src/main/resources/rawfile/format-registry/$taskFileName"
      $taskSourceDigest = (Get-FileHash -LiteralPath $taskSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($taskSourceDigest -ne $taskDigest) { throw "Packaged content differs from source: $taskName" }
    }
    $taskEvidence += [ordered]@{ name=$taskName; bytes=$taskEntry.Length; sha256=$taskDigest }
  }
  $taskReport = [ordered]@{
    scope='hap_package_inspection_not_device_execution'; result='passed';
    hap=$taskHapPath; hapBytes=(Get-Item -LiteralPath $taskHapPath).Length;
    hapSha256=(Get-FileHash -LiteralPath $taskHapPath -Algorithm SHA256).Hash.ToLowerInvariant();
    inspectedEntries=$taskEvidence; rawfileMatchesSource=$true;
    signing='unsigned'; deviceValidation='not_executed'; realConversion='not_executed'
  }
  $taskReportPath = Join-Path $taskProjectRoot 'tests/generated/hap-package-report.json'
  $taskReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $taskReportPath -Encoding utf8
  $taskReport | ConvertTo-Json -Depth 8
}
finally { $taskArchive.Dispose() }
