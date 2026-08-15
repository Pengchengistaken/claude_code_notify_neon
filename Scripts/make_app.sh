#!/bin/bash
# 把 SwiftPM 的构建产物组装成一个可运行的 NeonNotify.app。
# 这台机器只有 Command Line Tools，没有 Xcode，所以 .app 由脚本手工拼。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="NeonNotify"
BUNDLE_ID="com.lipengcheng.neonnotify"
VERSION="1.0.0"
BUILD="1"

APP="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP/Contents"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
# hook 必须和主程序放在一起：settings.json 里写的是它的绝对路径
cp "$BIN_DIR/neon-hook" "$CONTENTS/MacOS/neon-hook"

# SwiftPM 生成的资源包（ColorfulX 等）
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$CONTENTS/Resources/"
done

# 自带的资源（图标等），有就拷
if [ -d "$ROOT/Resources" ]; then
    cp -R "$ROOT/Resources/." "$CONTENTS/Resources/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <!-- 菜单栏应用：不进 Dock -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> ad-hoc 签名"
# UNUserNotificationCenter 要求 bundle 已签名；本地自用 ad-hoc 即可
codesign --force --sign - --timestamp=none "$CONTENTS/MacOS/neon-hook"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "==> 完成: $APP"
echo "    运行: open \"$APP\""
echo "    安装: cp -R \"$APP\" /Applications/   # 装到 /Applications 后再安装 hooks，路径才稳定"
