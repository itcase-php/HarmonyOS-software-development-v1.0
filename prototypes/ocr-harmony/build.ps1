param(
  [Parameter(Mandatory=$true)][string]$SdkRoot,
  [ValidateSet('arm64-v8a','x86_64')][string]$Abi='arm64-v8a'
)
$ErrorActionPreference='Stop'
$taskRepo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$taskRoot=Join-Path $taskRepo 'tmp/offline-engines'
$taskManifest=Get-Content (Join-Path $PSScriptRoot 'dependencies.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $taskRoot | Out-Null
function Fetch-Verified([string]$Url,[string]$Path,[string]$Sha) {
  if(!(Test-Path -LiteralPath $Path)){Invoke-WebRequest $Url -OutFile $Path}
  if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha){throw "SHA256 mismatch: $Path"}
}
function Invoke-Cmake([string[]]$Arguments,[string]$Log) {
  & cmake @Arguments *> $Log
  if($LASTEXITCODE -ne 0){Get-Content $Log -Tail 20;throw "CMake failed. See $Log"}
}
foreach($taskName in @('leptonica','tesseract')) {
  $taskDependency=$taskManifest.$taskName
  $taskArchive=Join-Path $taskRoot "$taskName-$($taskDependency.version).tar.gz"
  Fetch-Verified $taskDependency.url $taskArchive $taskDependency.sha256
  if(!(Test-Path (Join-Path $taskRoot "$taskName-$($taskDependency.version)"))){
    & tar -xf $taskArchive -C $taskRoot
    if($LASTEXITCODE -ne 0){throw 'Archive extraction failed'}
  }
}
$taskSuffix=if($Abi -eq 'arm64-v8a'){'arm64'}else{'x86_64'}
$taskInstall=Join-Path $taskRoot "install-$taskSuffix"
$taskToolchain=Join-Path $SdkRoot 'hms/native/build/cmake/hmos.toolchain.bisheng.cmake'
$taskNative=Join-Path $SdkRoot 'openharmony/native'
$taskCommon=@('-Wno-author','-Wno-deprecated','-G','Ninja',"-DCMAKE_TOOLCHAIN_FILE=$taskToolchain",
  "-DOHOS_SDK_NATIVE=$taskNative","-DOHOS_ARCH=$Abi",'-DCMAKE_BUILD_TYPE=Release',
  "-DCMAKE_INSTALL_PREFIX=$taskInstall",'-DBUILD_SHARED_LIBS=OFF','-DCMAKE_POSITION_INDEPENDENT_CODE=ON','-DSW_BUILD=OFF')
$taskLept=Join-Path $taskRoot "lept-$taskSuffix"
$taskOptions=@('-DBUILD_PROG=OFF')
foreach($taskCodec in @('ZLIB','PNG','GIF','JPEG','TIFF','WEBP','OPENJPEG')){$taskOptions+="-DENABLE_$taskCodec=OFF"}
Invoke-Cmake (@('-S', (Join-Path $taskRoot "leptonica-$($taskManifest.leptonica.version)"),'-B',$taskLept)+$taskCommon+$taskOptions) (Join-Path $taskRoot "lept-$taskSuffix-configure.log")
Invoke-Cmake @('--build',$taskLept,'--parallel','4') (Join-Path $taskRoot "lept-$taskSuffix-build.log")
Invoke-Cmake @('--install',$taskLept) (Join-Path $taskRoot "lept-$taskSuffix-install.log")
$taskTess=Join-Path $taskRoot "tess-$taskSuffix"
# TIFF is intentionally not built. This is a known configuration fact, not a simulated target try_run.
# CMP0137 forwards the SDK variables into upstream's whole-project IPO test.
$taskOptions=@("-DLeptonica_DIR=$taskInstall/lib/cmake/leptonica",'-DBUILD_TRAINING_TOOLS=OFF',
  '-DBUILD_TESTS=OFF','-DOPENMP_BUILD=OFF','-DGRAPHICS_DISABLED=ON','-DDISABLED_LEGACY_ENGINE=ON',
  '-DENABLE_NATIVE=OFF','-DENABLE_LTO=OFF','-DDISABLE_TIFF=ON','-DDISABLE_ARCHIVE=ON','-DDISABLE_CURL=ON',
  '-DCMAKE_POLICY_DEFAULT_CMP0137=NEW','-DLEPT_TIFF_RESULT=1')
Invoke-Cmake (@('-S',(Join-Path $taskRoot "tesseract-$($taskManifest.tesseract.version)"),'-B',$taskTess)+$taskCommon+$taskOptions) (Join-Path $taskRoot "tess-$taskSuffix-configure.log")
Invoke-Cmake @('--build',$taskTess,'--parallel','4') (Join-Path $taskRoot "tess-$taskSuffix-build.log")
Invoke-Cmake @('--install',$taskTess) (Join-Path $taskRoot "tess-$taskSuffix-install.log")
$taskProbe=Join-Path $taskRoot "probe-$taskSuffix"
Invoke-Cmake (@('-S',$PSScriptRoot,'-B',$taskProbe)+$taskCommon+@("-DOCR_ENGINE_ROOT=$taskInstall")) (Join-Path $taskRoot "probe-$taskSuffix-configure.log")
Invoke-Cmake @('--build',$taskProbe,'--parallel','4') (Join-Path $taskRoot "probe-$taskSuffix-build.log")
$taskModels=Join-Path $taskRoot 'models'
New-Item -ItemType Directory -Force -Path $taskModels | Out-Null
Fetch-Verified "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/$($taskManifest.models.commit)/LICENSE" (Join-Path $taskModels 'LICENSE') $taskManifest.models.licenseSha256
foreach($taskLanguage in @('eng','chi_sim')) {
  Fetch-Verified "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/$($taskManifest.models.commit)/$taskLanguage.traineddata" (Join-Path $taskModels "$taskLanguage.traineddata") $taskManifest.models.$taskLanguage
}
Write-Output "OCR libraries and NAPI probe built for $Abi. Device recognition is a separate check."
