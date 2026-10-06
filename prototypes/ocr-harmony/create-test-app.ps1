param([Parameter(Mandatory=$true)][string]$SdkRoot)
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath (Join-Path $SdkRoot 'openharmony/native'))){throw 'HarmonyOS SDK not found'}
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskEngineRoot=Join-Path $taskRepo 'tmp/offline-engines'
$taskManifest=Get-Content (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
$taskApp=Join-Path $taskEngineRoot 'stage-probe-app'
New-Item -ItemType Directory -Force -Path $taskApp | Out-Null
# Reuse the installed project's SDK/Stage template and local signing profile.
# This directory stays outside Git; signing content is never printed or published.
foreach($taskFile in @('build-profile.json5','hvigorfile.ts','oh-package.json5')){
  Copy-Item -LiteralPath (Join-Path $taskRepo $taskFile) -Destination (Join-Path $taskApp $taskFile)
}
foreach($taskDirectory in @('AppScope','hvigor')){
  Copy-Item -LiteralPath (Join-Path $taskRepo $taskDirectory) -Destination $taskApp -Recurse -Force
}
$taskEntry=Join-Path $taskApp 'entry'
New-Item -ItemType Directory -Force -Path "$taskEntry/src/main/ets/entryability","$taskEntry/src/main/ets/pages","$taskEntry/src/main/cpp/types","$taskEntry/src/main/resources/rawfile","$taskEntry/src/main/resources/base/profile" | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRepo 'entry/hvigorfile.ts') -Destination $taskEntry
Copy-Item -LiteralPath (Join-Path $taskRepo 'entry/build-profile.json5') -Destination $taskEntry
Copy-Item -LiteralPath (Join-Path $taskRepo 'entry/src/main/resources/base') -Destination "$taskEntry/src/main/resources" -Recurse -Force
@'
{
  "module": {
    "name": "entry", "type": "entry", "srcEntry": "./ets/entryability/EntryAbility.ets",
    "mainElement": "EntryAbility", "deviceTypes": ["phone"],
    "deliveryWithInstall": true, "installationFree": false, "pages": "$profile:main_pages",
    "abilities": [{
      "name": "EntryAbility", "srcEntry": "./ets/entryability/EntryAbility.ets",
      "icon": "$media:layered_image", "label": "$string:EntryAbility_label",
      "startWindowIcon": "$media:startIcon", "startWindowBackground": "$color:start_window_background",
      "exported": true, "skills": [{"entities":["entity.system.home"],"actions":["ohos.want.action.home"]}]
    }]
  }
}
'@ | Set-Content "$taskEntry/src/main/module.json5" -Encoding utf8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Index.ets') -Destination "$taskEntry/src/main/ets/pages"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'types') -Destination "$taskEntry/src/main/cpp/types/libhdm_ocr_probe" -Recurse -Force
foreach($taskModel in @('eng','chi_sim')) {
  Copy-Item -LiteralPath (Join-Path $taskEngineRoot "models/$taskModel.traineddata") -Destination "$taskEntry/src/main/resources/rawfile"
}
Copy-Item -LiteralPath (Join-Path $taskEngineRoot "leptonica-$($taskManifest.leptonica.version)/leptonica-license.txt") -Destination "$taskEntry/src/main/resources/rawfile/Leptonica-LICENSE.txt"
Copy-Item -LiteralPath (Join-Path $taskEngineRoot "tesseract-$($taskManifest.tesseract.version)/LICENSE") -Destination "$taskEntry/src/main/resources/rawfile/Tesseract-LICENSE.txt"
Copy-Item -LiteralPath (Join-Path $taskEngineRoot 'models/LICENSE') -Destination "$taskEntry/src/main/resources/rawfile/tessdata-fast-LICENSE.txt"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dependencies.json') -Destination "$taskEntry/src/main/resources/rawfile/ocr-dependencies.json"
# Generate a public synthetic raster, embedding no font file or user document.
$taskImage=New-Object System.Drawing.Bitmap 1400,260
$taskGraphics=[System.Drawing.Graphics]::FromImage($taskImage)
$taskGraphics.Clear([System.Drawing.Color]::White)
$taskFont=New-Object System.Drawing.Font 'Microsoft YaHei',40
$taskGraphics.DrawString('Harmony offline OCR 12345',$taskFont,[System.Drawing.Brushes]::Black,30,15)
$taskGraphics.DrawString('鸿蒙离线文档转换 67890',$taskFont,[System.Drawing.Brushes]::Black,30,130)
$taskPixels=New-Object byte[] (1400*260)
for($taskY=0;$taskY -lt 260;$taskY++) {for($taskX=0;$taskX -lt 1400;$taskX++) {$taskPixels[$taskY*1400+$taskX]=$taskImage.GetPixel($taskX,$taskY).R}}
$taskOutput=[System.IO.File]::Open("$taskEntry/src/main/resources/rawfile/ocr-fixture.pgm",[System.IO.FileMode]::Create)
try {
  $taskHeader=[System.Text.Encoding]::ASCII.GetBytes("P5`n1400 260`n255`n")
  $taskOutput.Write($taskHeader,0,$taskHeader.Length);$taskOutput.Write($taskPixels,0,$taskPixels.Length)
} finally {$taskOutput.Dispose();$taskGraphics.Dispose();$taskFont.Dispose();$taskImage.Dispose()}
& node (Join-Path $PSScriptRoot 'generate-pdf-fixture.cjs') "$taskEntry/src/main/resources/rawfile"
if($LASTEXITCODE -ne 0){throw 'PDF fixture generation failed'}
@'
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
}
'@ | Set-Content "$taskEntry/src/main/ets/entryability/EntryAbility.ets" -Encoding utf8
'{"src":["pages/Index"]}' | Set-Content "$taskEntry/src/main/resources/base/profile/main_pages.json" -Encoding utf8
'{"name":"entry","version":"0.0.1","dependencies":{"libhdm_ocr_probe.so":"file:./src/main/cpp/types/libhdm_ocr_probe"}}' | Set-Content "$taskEntry/oh-package.json5" -Encoding utf8
$taskBuildProfile=@{
  apiType='stageMode'
  buildOption=@{externalNativeOptions=@{path='./src/main/cpp/CMakeLists.txt';
    arguments="-DOCR_INSTALL_ROOT=$($taskEngineRoot.Replace('\','/')) -DOCR_PROBE_SOURCE=$($PSScriptRoot.Replace('\','/'))";abiFilters=@('arm64-v8a','x86_64')}}
  targets=@(@{name='default'})
}
$taskBuildProfile | ConvertTo-Json -Depth 6 | Set-Content "$taskEntry/build-profile.json5" -Encoding utf8
@'
cmake_minimum_required(VERSION 3.24)
project(hdm_stage_ocr_probe LANGUAGES CXX)
if(OHOS_ARCH STREQUAL "arm64-v8a")
  set(OCR_ENGINE_ROOT "${OCR_INSTALL_ROOT}/install-arm64")
else()
  set(OCR_ENGINE_ROOT "${OCR_INSTALL_ROOT}/install-x86_64")
endif()
add_subdirectory("${OCR_PROBE_SOURCE}" ocr-probe)
'@ | Set-Content "$taskEntry/src/main/cpp/CMakeLists.txt" -Encoding utf8
Write-Output "Standalone OCR Stage app created at $taskApp. Build it with DevEco/Hvigor."
Write-Output 'It uses the existing signing identity. Reinstall the converter HAP after testing.'
