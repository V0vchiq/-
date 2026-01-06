# Скрипт сборки llama.cpp для Android без CPU оптимизаций
# Требует: Android NDK, CMake, Git

$ErrorActionPreference = "Stop"

$PROJECT_DIR = Split-Path -Parent $PSScriptRoot
$LLAMA_DIR = "$PROJECT_DIR\llama.cpp"
$OUTPUT_DIR = "$PROJECT_DIR\android\app\src\main\jniLibs\arm64-v8a"
$NDK_PATH = $env:ANDROID_NDK_HOME
if (-not $NDK_PATH) {
    $NDK_PATH = "$env:LOCALAPPDATA\Android\Sdk\ndk\27.0.12077973"
}
$CMAKE_PATH = "$env:LOCALAPPDATA\Android\Sdk\cmake\3.22.1\bin\cmake.exe"

Write-Host "=== Building llama.cpp for Android ===" -ForegroundColor Cyan
Write-Host "NDK: $NDK_PATH"
Write-Host "Output: $OUTPUT_DIR"

# Клонируем llama.cpp если нет
if (-not (Test-Path $LLAMA_DIR)) {
    Write-Host "Cloning llama.cpp..." -ForegroundColor Yellow
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git $LLAMA_DIR
}

# Создаём build директорию
$BUILD_DIR = "$LLAMA_DIR\build-android"
if (Test-Path $BUILD_DIR) {
    Remove-Item -Recurse -Force $BUILD_DIR
}
New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null

Set-Location $BUILD_DIR

# CMake конфигурация с базовыми ARM флагами (без оптимизаций)
Write-Host "Configuring CMake..." -ForegroundColor Yellow
& $CMAKE_PATH .. `
    -G "Ninja" `
    -DCMAKE_MAKE_PROGRAM="$env:LOCALAPPDATA\Android\Sdk\cmake\3.22.1\bin\ninja.exe" `
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH\build\cmake\android.toolchain.cmake" `
    -DANDROID_ABI=arm64-v8a `
    -DANDROID_PLATFORM=android-26 `
    -DANDROID_STL=c++_shared `
    -DCMAKE_BUILD_TYPE=Release `
    -DGGML_NATIVE=OFF `
    -DGGML_CPU_ARM_ARCH=armv8-a `
    -DGGML_OPENMP=OFF `
    -DGGML_VULKAN=OFF `
    -DLLAMA_BUILD_TESTS=OFF `
    -DLLAMA_BUILD_EXAMPLES=OFF `
    -DLLAMA_BUILD_SERVER=OFF `
    -DLLAMA_BUILD_TOOLS=OFF `
    -DLLAMA_BUILD_COMMON=OFF `
    -DLLAMA_CURL=OFF `
    -DBUILD_SHARED_LIBS=ON

# Собираем
Write-Host "Building..." -ForegroundColor Yellow
& $CMAKE_PATH --build . --config Release -j $env:NUMBER_OF_PROCESSORS

# Копируем библиотеки
Write-Host "Copying libraries..." -ForegroundColor Yellow
$libs = @(
    "bin\libggml.so",
    "bin\libggml-base.so",
    "bin\libggml-cpu.so",
    "bin\libllama.so"
)

foreach ($lib in $libs) {
    $src = "$BUILD_DIR\$lib"
    if (Test-Path $src) {
        Copy-Item $src $OUTPUT_DIR -Force
        Write-Host "Copied: $lib" -ForegroundColor Green
    } else {
        Write-Host "Not found: $lib" -ForegroundColor Red
    }
}

# Удаляем Vulkan библиотеку (не используем)
$vulkanLib = "$OUTPUT_DIR\libggml-vulkan.so"
if (Test-Path $vulkanLib) {
    Remove-Item $vulkanLib -Force
    Write-Host "Removed libggml-vulkan.so (not needed)" -ForegroundColor Yellow
}

Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Now run 'flutter clean && flutter run'" -ForegroundColor White

Set-Location $PROJECT_DIR
