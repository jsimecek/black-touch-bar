# black-touch-bar - 2026

A tiny macOS app that blacks out the Touch Bar.

No SIP changes, no sudo, no kernel hacks, no permissions needed -- just a black overlay using Apple's own (private) Touch Bar API.

## Motivation

I know there is the popular Hide My Bar app, but I like my apps free and open source, so anyone can tweak them to their liking and check the code to make sure it's not doing anything malicious. Also, their app requires some troubleshooting hacks for it to work with Function Keys (F1, F2, etc...), where as this app works out of the box with every Touch Bar setup (I think).

## How it works

There's no public API to control the Touch Bar backlight. BlackTouchBar works around this by presenting a system-modal black overlay that covers the entire Touch Bar display using Apple's private `NSTouchBar` and `DFRFoundation` APIs. Since the LCD is showing pure black, almost no light passes through. This is the same technique as Hide My Bar app uses. To make it work with Function Keys and other setups, the app saves the current Touch Bar settings, switches to App Controls to do the blackout and restores them after the black overlay is removed.

## Requirements

- macOS 12+ (Monterey or later)
- MacBook Pro with Touch Bar
- Xcode Command Line Tools for building (`xcode-select --install`)

## Build & install

```bash
# 1. Clone the repo
git clone https://github.com/jsimecek/black-touch-bar.git BlackTouchBar
cd BlackTouchBar

# 2. Compile the Swift source into a .app bundle
mkdir -p BlackTouchBar.app/Contents/MacOS
swiftc -O BlackTouchBar.swift \
    -o BlackTouchBar.app/Contents/MacOS/BlackTouchBar \
    -framework AppKit \
    -F /System/Library/PrivateFrameworks \
    -framework DFRFoundation

# 3. Add the Info.plist so macOS treats it as a background app (no Dock icon)
cat > BlackTouchBar.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BlackTouchBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.BlackTouchBar</string>
    <key>CFBundleName</key>
    <string>BlackTouchBar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# 4. Move the app to /Applications
cp -R BlackTouchBar.app /Applications/
```

## Usage

### Start the app

```bash
open /Applications/BlackTouchBar.app
```

The app now runs in the background.

### Toggle the Touch Bar black

| Method               | How                                                    |
| -------------------- | ------------------------------------------------------ |
| **Double-press Cmd** | Press and release the Cmd key twice within 0.4 seconds |
| **Shell script**     | Run `./toggle-touchbar.sh` (included in this repo)     |
| **macOS Shortcuts**  | Create a shortcut that runs the shell script above     |

### Auto-start at login

> System Settings > General > Login Items > click **+** > select **BlackTouchBar**

### Quit

The Touch Bar is automatically restored when the app exits. To quit:

```bash
pkill -x BlackTouchBar
```

## Uninstall

```bash
rm -rf /Applications/BlackTouchBar.app
```

## License

MIT
