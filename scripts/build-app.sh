#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

APP=".build/Codex Usage.app"
BIN=".build/release/CodexUsage"
VERSION="${VERSION:-0.1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# --install   构建后替换 /Applications 里的包（「登录时自动启动」要求 App 在启动磁盘上）
# --universal 同时编出 arm64 与 x86_64 两个切片再 lipo，供发布用
INSTALL="${INSTALL:-0}"
UNIVERSAL="${UNIVERSAL:-0}"
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    *) print -u2 "未知参数：$arg（可用：--install、--universal）"; exit 2 ;;
  esac
done

# 通过 SwiftPM 构建，确保第三方模块（例如 ConfettiSwiftUI）参与编译。
build_with_swiftpm() {
  swift build -c release
}

if [[ "$UNIVERSAL" == "1" ]]; then
  # 不同架构分别使用独立 scratch path，避免 SwiftPM 覆盖另一架构的产物。
  ARM64_BUILD=".build/swiftpm-arm64"
  X86_64_BUILD=".build/swiftpm-x86_64"
  swift build -c release --triple arm64-apple-macosx13.0 --scratch-path "$ARM64_BUILD"
  swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path "$X86_64_BUILD"
  lipo -create -output "$BIN" \
    "$ARM64_BUILD/out/Products/Release/CodexUsage" \
    "$X86_64_BUILD/out/Products/Release/CodexUsage"
elif [[ "${BUILD_WITH_SWIFTC:-0}" == "1" || ! -w "$HOME/Library/Caches" ]]; then
  # 即使系统缓存不可写也使用 SwiftPM；第三方模块无法由直接 swiftc 编译。
  build_with_swiftpm
elif ! build_with_swiftpm; then
  echo "SwiftPM 构建失败；项目依赖第三方 SwiftPM 模块，不能回退到 swiftc。" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CodexUsage"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsage</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>dev.local.CodexUsage</string>
<key>CFBundleName</key><string>Codex Usage</string>
<key>CFBundleShortVersionString</key><string>__VERSION__</string>
<key>CFBundleVersion</key><string>__BUILD__</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# 版本号统一由 $VERSION / $BUILD_NUMBER 注入，免得 plist 里的版本和发布包名对不上。
sed -i '' -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $APP  v$VERSION  arch=$(lipo -archs "$APP/Contents/MacOS/CodexUsage" 2>/dev/null || echo unknown)"

# --install：顺手装到 /Applications。
# 登录项要求 App 在启动磁盘上，而且这个脚本每次构建都会删掉 .build 里的包，
# 登录项指向构建目录必然失效 —— 所以自启动功能要配合这个开关用。
if [[ "$INSTALL" == "1" ]]; then
  DEST="/Applications/Codex Usage.app"
  pkill -f "$DEST/Contents/MacOS/CodexUsage" 2>/dev/null || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  echo "Installed: $DEST"
fi
