# build_local.ps1 — reproducible local build of nano_ffi.pyd on this Windows box.
# Uses the Zig 0.15.2 toolchain in LOCALAPPDATA and the active CPython's headers/libs.
$ErrorActionPreference = "Stop"

$zig = "$env:LOCALAPPDATA\zig-0.15.2\zig.exe"

$pyInclude = & python -c "import sysconfig; print(sysconfig.get_path('include'))"
$pyBase    = & python -c "import sysconfig, os; print(os.path.dirname(sysconfig.get_path('include')))"
$pyLibs    = Join-Path $pyBase "libs"
$pyTag     = & python -c "import sys; print(f'python{sys.version_info.major}{sys.version_info.minor}')"

Write-Host "Zig:      $zig"
Write-Host "Include:  $pyInclude"
Write-Host "Libs:     $pyLibs"
Write-Host "Libname:  $pyTag"

& $zig build -Doptimize=ReleaseFast `
  -Dpython-include="$pyInclude" `
  -Dpython-lib="$pyLibs" `
  -Dpython-libname="$pyTag"

if ($LASTEXITCODE -ne 0) { throw "zig build failed ($LASTEXITCODE)" }

Copy-Item "zig-out\lib\nano_ffi.pyd" "nano_ffi.pyd" -Force
Write-Host "OK -> nano_ffi.pyd"
