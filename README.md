# BlackTouchBar

A tiny macOS menu-bar app that blacks out the Touch Bar so it doesn't light up when you're working at night.

No SIP changes, no sudo, no kernel hacks -- just a black overlay using Apple's own (private) Touch Bar API.

## How it works

There's no public API to control the Touch Bar backlight. BlackTouchBar works around this by presenting a system-modal black view that covers the entire Touch Bar display. Since the LCD is showing pure black, almost no light passes through.

## Requirements

- macOS 12+ (Monterey or later)
- MacBook Pro with Touch Bar
- Xcode Command Line Tools (`xcode-select --install`)

## Build & install

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/BlackTouchBar.git
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

# 4. Move the app to ~/Applications
mkdir -p ~/Applications
cp -R BlackTouchBar.app ~/Applications/
```

## Usage

### Start the app

```bash
open ~/Applications/BlackTouchBar.app
```

A **"TB"** item appears in the menu bar.

### Toggle the Touch Bar black

Pick whichever method you prefer:

| Method | How |
|---|---|
| **Double-press Cmd** | Press and release the Cmd key twice within 0.4 seconds |
| **Menu bar** | Click the "TB" icon > "Toggle Touch Bar" |
| **Shell script** | Run `./toggle-touchbar.sh` (included in this repo) |
| **macOS Shortcuts** | Create a shortcut that runs the shell script above |

### Auto-start at login

System Settings > General > Login Items > click **+** > select `BlackTouchBar.app` from `~/Applications`

### Quit

Click the menu bar icon > **Quit**. The Touch Bar is automatically restored to its previous state.

## Permissions

On first launch, macOS may ask for **Accessibility** permissions (needed for the double-Cmd hotkey). Grant it in:

System Settings > Privacy & Security > Accessibility

If you skip this, the menu bar icon and script-based toggling still work -- only the keyboard shortcut won't.

## Limitations

- A small **X button** remains visible on the left edge of the Touch Bar. This is the system-modal dismiss control that macOS enforces and can't be removed without disabling SIP.
- The backlight stays on behind the black LCD, so there's a faint glow in a pitch-dark room. It's dramatically darker than active Touch Bar content, but not truly off.

## Uninstall

```bash
rm -rf ~/Applications/BlackTouchBar.app
```

## License

MIT
