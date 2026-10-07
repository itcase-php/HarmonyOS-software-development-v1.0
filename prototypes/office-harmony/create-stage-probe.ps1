$ErrorActionPreference = 'Stop'
$taskRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskApp = Join-Path $taskRepo 'tmp/offline-engines/office-stage-probe'
New-Item -ItemType Directory -Force -Path $taskApp | Out-Null
foreach ($taskFile in @('build-profile.json5','hvigorfile.ts','oh-package.json5','oh-package-lock.json5')) {
  Copy-Item -LiteralPath (Join-Path $taskRepo $taskFile) -Destination $taskApp -Force
}
foreach ($taskDirectory in @('AppScope','hvigor')) {
  Copy-Item -LiteralPath (Join-Path $taskRepo $taskDirectory) -Destination $taskApp -Recurse -Force
}
$taskEntry = Join-Path $taskApp 'entry'
New-Item -ItemType Directory -Force -Path "$taskEntry/src/main/ets/entryability","$taskEntry/src/main/ets/pages","$taskEntry/src/main/cpp/types/liboffice_probe","$taskEntry/src/main/resources/rawfile","$taskEntry/src/main/resources/base/profile","$taskEntry/libs/arm64-v8a" | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRepo 'entry/hvigorfile.ts') -Destination $taskEntry -Force
Copy-Item -LiteralPath (Join-Path $taskRepo 'entry/src/main/resources/base') -Destination "$taskEntry/src/main/resources" -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'StageIndex.ets') -Destination "$taskEntry/src/main/ets/pages/Index.ets" -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'stage_probe.cpp') -Destination "$taskEntry/src/main/cpp" -Force
Copy-Item -LiteralPath (Join-Path $taskRepo 'tmp/offline-engines/office-fixtures/layout.docx'),(Join-Path $taskRepo 'tmp/offline-engines/office-fixtures/layout.pptx') -Destination "$taskEntry/src/main/resources/rawfile" -Force
@'
{"module":{"name":"entry","type":"entry","srcEntry":"./ets/entryability/EntryAbility.ets","mainElement":"EntryAbility","deviceTypes":["phone"],"deliveryWithInstall":true,"installationFree":false,"pages":"$profile:main_pages","abilities":[{"name":"EntryAbility","srcEntry":"./ets/entryability/EntryAbility.ets","icon":"$media:layered_image","label":"$string:EntryAbility_label","startWindowIcon":"$media:startIcon","startWindowBackground":"$color:start_window_background","exported":true,"skills":[{"entities":["entity.system.home"],"actions":["ohos.want.action.home"]}]}]}}
'@ | Set-Content "$taskEntry/src/main/module.json5" -Encoding utf8
@'
import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
}
'@ | Set-Content "$taskEntry/src/main/ets/entryability/EntryAbility.ets" -Encoding utf8
'{"src":["pages/Index"]}' | Set-Content "$taskEntry/src/main/resources/base/profile/main_pages.json" -Encoding utf8
'{"name":"liboffice_probe.so","version":"0.0.1","types":"./index.d.ts"}' | Set-Content "$taskEntry/src/main/cpp/types/liboffice_probe/oh-package.json5" -Encoding utf8
'export const run: (root: string) => Promise<string>;' | Set-Content "$taskEntry/src/main/cpp/types/liboffice_probe/index.d.ts" -Encoding utf8
'{"name":"entry","version":"0.0.1","dependencies":{"liboffice_probe.so":"file:./src/main/cpp/types/liboffice_probe"}}' | Set-Content "$taskEntry/oh-package.json5" -Encoding utf8
'{"apiType":"stageMode","buildOption":{"externalNativeOptions":{"path":"./src/main/cpp/CMakeLists.txt","abiFilters":["arm64-v8a"]}},"targets":[{"name":"default"}]}' | Set-Content "$taskEntry/build-profile.json5" -Encoding utf8
@'
cmake_minimum_required(VERSION 3.18)
project(office_stage_probe LANGUAGES CXX)
add_library(office_probe SHARED stage_probe.cpp)
target_include_directories(office_probe PRIVATE include)
target_compile_features(office_probe PRIVATE cxx_std_17)
target_compile_definitions(office_probe PRIVATE LINUX UNX GCC)
target_link_libraries(office_probe PRIVATE libace_napi.z.so dl)
'@ | Set-Content "$taskEntry/src/main/cpp/CMakeLists.txt" -Encoding utf8
$taskHeaders = '\\wsl.localhost\Ubuntu\home\tx\.cache\hdm-office\26.2.6.2\source\include\LibreOfficeKit'
New-Item -ItemType Directory -Force -Path "$taskEntry/src/main/cpp/include" | Out-Null
Copy-Item -LiteralPath $taskHeaders -Destination "$taskEntry/src/main/cpp/include" -Recurse -Force
$taskOfficeRoot = '\\wsl.localhost\Ubuntu\home\tx\.cache\hdm-office\26.2.6.2'
foreach ($taskDirectory in @('sal','rtl','osl','typelib','cppu','com')) {
  Copy-Item -LiteralPath "$taskOfficeRoot/source/include/$taskDirectory" -Destination "$taskEntry/src/main/cpp/include" -Recurse -Force
}
Copy-Item -LiteralPath "$taskOfficeRoot/build-arm64/config_host/config_typesizes.h" -Destination "$taskEntry/src/main/cpp/include" -Force
foreach ($taskHeader in @('Exception','RuntimeException','DeploymentException')) {
  Copy-Item -LiteralPath "$taskOfficeRoot/build-arm64/workdir/UnoApiHeadersTarget/udkapi/normal/com/sun/star/uno/$taskHeader.hdl" -Destination "$taskEntry/src/main/cpp/include/com/sun/star/uno" -Force
}
Write-Output $taskApp
