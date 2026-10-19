# =============================================================================
# Windows 完整打包脚本：Python 后端（PyInstaller）+ Flutter 前端
#
# 用法：在仓库根目录（PowerShell）执行  .\scripts\build_windows.ps1
# 前置条件：
#   1. 已安装 Python 3.10+ 并加入 PATH（python 可执行）
#   2. 已安装 Flutter 3.35+（flutter doctor 通过 Windows 部分，含 VS 工具链）
#   3. pip install -r python_backend/requirements.txt（含 pyinstaller）
#
# 产物：
#   - build\windows\x64\runner\Release\（前端 exe + 内嵌后端）
#   打包后的目录整体压缩（zip）即可分发；Inno Setup 可进一步做安装器。
# =============================================================================
$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$BackendDir = Join-Path $RootDir "python_backend"
$ReleaseDir = Join-Path $RootDir "build\windows\x64\runner\Release"

Write-Host "==> [1/3] PyInstaller 打包 Python 后端"
Push-Location $BackendDir
pyinstaller build.spec --noconfirm --clean
if ($LASTEXITCODE -ne 0) { throw "PyInstaller 打包失败" }
Pop-Location

Write-Host "==> [2/3] Flutter 构建 Windows 应用（Release）"
Push-Location $RootDir
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Flutter 构建失败" }
Pop-Location

Write-Host "==> [3/3] 将后端复制到应用 Release 目录（exe 同级 python_backend\）"
$TargetBackend = Join-Path $ReleaseDir "python_backend"
if (Test-Path $TargetBackend) { Remove-Item -Recurse -Force $TargetBackend }
Copy-Item -Recurse (Join-Path $BackendDir "dist\ai_agent_backend") $TargetBackend
# 前端 ProcessManager 在 exe 同目录探测 python_backend\ai_agent_backend.exe

Write-Host ""
Write-Host "打包完成：$ReleaseDir"
Write-Host "分发方式：将该目录整体 zip 压缩发给用户（或用 Inno Setup 制作安装器）"
