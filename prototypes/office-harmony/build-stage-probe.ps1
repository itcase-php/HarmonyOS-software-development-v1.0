param([switch]$Install)
$ErrorActionPreference = 'Stop'
$taskRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskApp = Join-Path $taskRepo 'tmp/offline-engines/office-stage-probe'
$taskMain = Join-Path $taskApp 'entry/src/main'
New-Item -ItemType Directory -Path "$taskMain/ets/services" -Force | Out-Null
New-Item -ItemType Directory -Path "$taskMain/ets/models" -Force | Out-Null
Copy-Item -LiteralPath "$taskRepo/entry/src/main/ets/models/NativeProtocol.ets" -Destination "$taskMain/ets/models" -Force
Copy-Item -LiteralPath "$PSScriptRoot/stage_probe.cpp" -Destination "$taskMain/cpp/stage_probe.cpp" -Force
Copy-Item -LiteralPath "$PSScriptRoot/StageIndex.ets" -Destination "$taskMain/ets/pages/Index.ets" -Force
Copy-Item -LiteralPath "$PSScriptRoot/PdfRebuildProbe.ets" -Destination "$taskMain/ets/services" -Force
Copy-Item -LiteralPath "$taskRepo/entry/src/main/ets/services/OfficePackageWriter.ets" -Destination "$taskMain/ets/services" -Force
Copy-Item -LiteralPath "$taskRepo/entry/src/main/ets/services/PdfOfficeConverter.ets" -Destination "$taskMain/ets/services" -Force
Copy-Item -LiteralPath "$taskRepo/tmp/offline-engines/office-fixtures/editable-input.pdf" -Destination "$taskMain/resources/rawfile" -Force
$env:DEVECO_SDK_HOME = 'D:/DevEco Studio2026/DevEco Studio/sdk'
Push-Location $taskApp
try {
  & 'D:/DevEco Studio2026/DevEco Studio/tools/node/node.exe' 'D:/DevEco Studio2026/DevEco Studio/tools/hvigor/bin/hvigorw.js' --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon > ../office-stage-build.log 2>&1
  if ($LASTEXITCODE -ne 0) { Get-Content ../office-stage-build.log -Tail 55; throw 'Office stage build failed' }
  Get-Content ../office-stage-build.log -Tail 4
  if ($Install) {
    $taskHap = (Resolve-Path 'entry/build/default/outputs/default/entry-default-signed.hap').Path
    $taskInstallResult = & 'D:/DevEco Studio2026/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' install -r $taskHap 2>&1
    Write-Output $taskInstallResult
    if ($LASTEXITCODE -ne 0 -or ($taskInstallResult -join "`n") -notmatch 'install bundle successfully') { throw 'Office stage install failed' }
    $taskStartResult = & 'D:/DevEco Studio2026/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' shell aa start -a EntryAbility -b com.example.os_softwaredevelopment 2>&1
    Write-Output $taskStartResult
    if (($taskStartResult -join "`n") -notmatch 'start ability successfully') { throw 'Office stage start failed' }
  }
} finally { Pop-Location }
