#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

# 打发布包：通用二进制 .app → dist/ 里的 .zip 与 .dmg。
#   VERSION=0.1.2 ./scripts/package-release.sh
#   SKIP_DMG=1 ./scripts/package-release.sh    # 只出 zip
# 版本号同时进 Info.plist 和文件名，免得两者对不上。
VERSION="${VERSION:-0.1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SKIP_DMG="${SKIP_DMG:-0}"
DIST="dist"
NAME="CodexUsage-$VERSION"
APP=".build/Codex Usage.app"
ZIP="$DIST/$NAME-macos.zip"
DMG="$DIST/$NAME.dmg"

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./scripts/build-app.sh --universal

[[ -d "$APP" ]] || { print -u2 "没找到构建产物：$APP"; exit 1 }
mkdir -p "$DIST"
rm -f "$ZIP" "$DMG"

# zip：ditto 能正确保留 .app 包内的符号链接、权限与扩展属性（zip(1) 会丢）。
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if [[ "$SKIP_DMG" != "1" ]]; then
  # dmg：暂存目录里放 App + 一个 /Applications 软链，打开就能直接拖进去装。
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  ditto "$APP" "$STAGE/Codex Usage.app"
  ln -s /Applications "$STAGE/Applications"
  # 建 dmg 要 attach/mount 一块磁盘映像：受限沙箱会拒绝这一步（报 OSStatus error 1），
  # 所以这里失败只降级成「没有 dmg」，zip 照常产出。
  if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --volumeName "Codex Usage" --format UDZO "$STAGE" "$DMG" || DMG_OK=0
  else
    # 老系统没有 diskutil image 子命令，用 hdiutil（新系统上它已标记 deprecated）。
    hdiutil create -volname "Codex Usage" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG" || DMG_OK=0
  fi
  if [[ "${DMG_OK:-1}" == "0" || ! -f "$DMG" ]]; then
    print -u2 "⚠️  dmg 生成失败（通常是没有权限 attach 磁盘映像，例如受限沙箱）——本次只发布 zip。"
    rm -f "$DMG"
  fi
  rm -rf "$STAGE"
fi

echo "→ 发布包已生成："
ls -lh "$DIST"
FILES=("$ZIP")
[[ -f "$DMG" ]] && FILES+=("$DMG")
shasum -a 256 "${FILES[@]}" | sed 's|'"$PWD"'/||'
