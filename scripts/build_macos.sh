#!/usr/bin/env bash
# =============================================================================
# macOS 完整打包脚本：Python 后端（PyInstaller）+ Flutter 前端 + .dmg
#
# 用法：在仓库根目录执行  ./scripts/build_macos.sh
# 前置条件：
#   1. 已安装 Python 3.10+ 并可执行（含 pip）
#   2. 已安装 Flutter 3.35+（flutter doctor 通过 macOS 部分）
#   3. pip install -r python_backend/requirements.txt（含 pyinstaller）
#
# 产物：
#   - build/macos/Build/Products/Release/slagent.app（内嵌后端）
#   - dist/slagent.dmg
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/python_backend"
APP_NAME="slagent"
RELEASE_APP="$ROOT_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"

echo "==> [1/4] PyInstaller 打包 Python 后端"
(cd "$BACKEND_DIR" && pyinstaller build.spec --noconfirm --clean)
# 产物：python_backend/dist/ai_agent_backend/（onedir：含可执行文件与 _internal）

echo "==> [2/4] Flutter 构建 macOS 应用（Release）"
(cd "$ROOT_DIR" && flutter build macos --release)

echo "==> [3/4] 将后端嵌入 .app bundle（Contents/Resources/python_backend）"
RESOURCES_DIR="$RELEASE_APP/Contents/Resources"
rm -rf "$RESOURCES_DIR/python_backend"
cp -R "$BACKEND_DIR/dist/ai_agent_backend" "$RESOURCES_DIR/python_backend"
# 前端 ProcessManager 会向上探测 Resources/python_backend/ai_agent_backend

# 临时签名（ad-hoc）：本机可直接运行。
# 正式分发需替换为开发者证书并公证：
#   codesign --deep --force --options runtime --timestamp \
#     --sign "Developer ID Application: 你的证书" "$RELEASE_APP"
#   xcrun notarytool submit ... && xcrun stapler staple ...
codesign --force --deep --sign - "$RELEASE_APP" 2>/dev/null || \
  echo "   （跳过 ad-hoc 签名：未找到 codesign 或无需签名）"

echo "==> [4/4] 生成 .dmg 安装包"
mkdir -p "$ROOT_DIR/dist"
rm -f "$DMG_PATH"
hdiutil create -volname "slagent" \
  -srcfolder "$RELEASE_APP" \
  -ov -format UDZO "$DMG_PATH"

echo ""
echo "打包完成："
echo "  App: $RELEASE_APP"
echo "  DMG: $DMG_PATH"
