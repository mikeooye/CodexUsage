#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

APP=".build/Codex Usage.app"
BIN=".build/release/CodexUsage"
VERSION="${VERSION:-0.1.0}"
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

# 首选 SwiftPM（增量构建、快）。但在受限环境里（例如被沙箱挡住写 ~/Library 与
# 系统模块缓存）SwiftPM 的构建服务和 manifest 会失败 —— 这时退回直接调用 swiftc。
# 两条路径产物等价，都不需要额外权限或人工批准。
build_with_swiftpm() {
  swift build -c release
}

# 编译单个架构的切片：$1 = 架构，$2 = 输出路径。
compile_slice() {
  local arch="$1" out="$2"
  mkdir -p "${out:h}"
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macosx13.0" \
    -sdk "$(xcrun --show-sdk-path)" \
    -o "$out" Sources/CodexUsage/*.swift \
    -module-cache-path "$PWD/.build/swiftc/swift-cache" \
    -Xcc "-fmodules-cache-path=$PWD/.build/swiftc/clang-cache"
}

build_with_swiftc() {
  echo "→ 用 swiftc 直接编译（跳过 SwiftPM）"
  local scratch=".build/swiftc"
  mkdir -p "$scratch" .build/release
  # 把编译器缓存全部重定向进工作区，避免写系统目录被拒。
  export CLANG_MODULE_CACHE_PATH="$PWD/$scratch/clang-cache"
  if [[ "$UNIVERSAL" == "1" ]]; then
    compile_slice arm64 "$scratch/arm64/CodexUsage"
    compile_slice x86_64 "$scratch/x86_64/CodexUsage"
    lipo -create -output "$BIN" "$scratch/arm64/CodexUsage" "$scratch/x86_64/CodexUsage"
  else
    compile_slice "$(uname -m)" "$BIN"
  fi
}

if [[ "$UNIVERSAL" == "1" ]]; then
  # SwiftPM 要连跑两遍且产物互相覆盖，通用二进制直接编两个切片再 lipo 更可控。
  build_with_swiftc
elif [[ "${BUILD_WITH_SWIFTC:-0}" == "1" || ! -w "$HOME/Library/Caches" ]]; then
  # $HOME/Library 不可写 = 大概率在受限沙箱里，直接走 swiftc，省去 SwiftPM 那几十秒的失败等待。
  build_with_swiftc
elif ! build_with_swiftpm; then
  echo "→ SwiftPM 构建失败，回退到 swiftc"
  build_with_swiftc
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
