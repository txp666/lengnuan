# 被 preview.command / screenshots.command 引用：编译 Mac 上的界面预览程序到 build/Preview.app
ARCH="$(uname -m)"
APP="build/Preview.app"
echo "▶ 编译预览程序（${ARCH}）…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -Onone -parse-as-library \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target "${ARCH}-apple-macos14.0" \
  -module-name YorkPreview \
  -D PREVIEW_HARNESS \
  Sources/Shared/*.swift Sources/Intents/ACIntents.swift Sources/Widget/ACWidget.swift Sources/Preview/*.swift \
  -o "$APP/Contents/MacOS/YorkPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>YorkPreview</string>
  <key>CFBundleIdentifier</key><string>com.example.lengnuan.preview</string>
  <key>CFBundleName</key><string>冷暖预览</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
