# Shutter on Ubuntu 22.04 - Wayland Support

This document describes Shutter's compatibility with Ubuntu 22.04 (GNOME 42) and its support for both Wayland and X11 sessions.

## Overview

Ubuntu 22.04 uses Wayland by default in GNOME sessions. Shutter has been updated to work with both Wayland and X11, though some features have limitations on Wayland due to the compositor's security model.

## Session Detection

Shutter automatically detects your session type on startup:
- **Wayland session**: Uses XDG Desktop Portal and/or gnome-screenshot for captures
- **X11 session**: Uses native X11 methods (full feature support)

## Feature Support Matrix

| Feature | X11 | Wayland (with gnome-screenshot) | Wayland (portal only) |
|---------|-----|--------------------------------|----------------------|
| Full Screen | ✅ | ✅ | ✅ |
| Selection | ✅ | ✅ | ✅ (portal UI) |
| Window | ✅ | ✅ | ❌ |
| Active Window | ✅ | ✅ | ❌ |
| Menu | ✅ | ❌ | ❌ |
| Tooltip | ✅ | ❌ | ❌ |
| Include Cursor | ✅ | ✅ | ❌ |
| Delay | ✅ | ✅ | ❌ |
| Multi-monitor | ✅ | ✅ | ✅ |

### Notes on Feature Limitations

- **Menu/Tooltip capture**: These features are not possible on Wayland because the compositor doesn't expose information about popup windows to applications (security feature).
- **Window decorations**: On Wayland with gnome-screenshot, window decorations are always included. Client-side decoration handling may differ from X11.

## Installation on Ubuntu 22.04

### Required Dependencies

```bash
# Core dependencies
sudo apt install \
    perl \
    libgtk3-perl \
    libglib-perl \
    libnet-dbus-perl \
    libfile-which-perl \
    libwnck-3-0 \
    gir1.2-wnck-3.0 \
    libgoocanvas-2.0-9 \
    libgoocanvas2-perl \
    libgtk3-imageview-perl \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome

# For better Wayland support (recommended)
sudo apt install gnome-screenshot

# For wlroots-based compositors (Sway, etc.)
sudo apt install grim slurp
```

### Optional Dependencies

```bash
# For web capture
sudo apt install gnome-web-photo

# For image editing
sudo apt install perlmagick

# For EXIF data
sudo apt install libimage-exiftool-perl

# For file sharing
sudo apt install nautilus-sendto
```

## Running Shutter

### On Wayland (default in Ubuntu 22.04)

Simply run:
```bash
shutter
```

Shutter will automatically detect the Wayland session and enable available features.

### On X11 Session

To run with full feature support, log out and select "Ubuntu on Xorg" at the login screen, then run:
```bash
shutter
```

### Force X11 Backend (XWayland)

If you need X11 features while in a Wayland session:
```bash
GDK_BACKEND=x11 shutter
```

**Note**: This runs Shutter through XWayland and may have some quirks.

## Troubleshooting

### "Selection button is disabled"

On Wayland, the Selection button requires either:
1. `gnome-screenshot` installed (recommended)
2. `grim` + `slurp` installed (for wlroots compositors)
3. XDG Desktop Portal with screenshot support

Install gnome-screenshot:
```bash
sudo apt install gnome-screenshot
```

### "Full screen capture fails"

Ensure XDG Desktop Portal is running:
```bash
systemctl --user status xdg-desktop-portal
systemctl --user restart xdg-desktop-portal
```

### "Window capture not available"

Window capture on Wayland requires gnome-screenshot:
```bash
sudo apt install gnome-screenshot
```

If window capture still doesn't work, you may need to switch to an X11 session.

### Screenshots are blank or black

This can happen if:
1. The portal backend doesn't match your compositor
2. Permission dialogs are being shown but not visible

Try:
```bash
# Restart the portal service
systemctl --user restart xdg-desktop-portal-gnome
```

### High DPI / Scaling Issues

If screenshots appear scaled incorrectly, try setting:
```bash
GDK_SCALE=1 shutter
```

## Testing Your Setup

Run the backend test script to verify your configuration:

```bash
perl t/backend_test.pl
```

This will show:
- Detected session type (X11 or Wayland)
- Available capture backends
- Which features are enabled

## Development and Debugging

### Enable Debug Output

```bash
shutter --debug
```

### Check Backend Detection

```bash
echo $XDG_SESSION_TYPE
# Should output "wayland" or "x11"

echo $WAYLAND_DISPLAY
# Should be set if running on Wayland (e.g., "wayland-0")
```

### Test XDG Portal

```bash
# Check if portal is running
busctl --user status org.freedesktop.portal.Desktop

# Test screenshot via D-Bus
gdbus call --session \
    --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Screenshot.Screenshot \
    "" {}
```

## Architecture

### Capture Backend Flow

```
User clicks capture button
        │
        ▼
Backend detection (Backend.pm)
        │
        ├─► X11 detected
        │      └─► Use native Screenshot modules
        │
        └─► Wayland detected
               │
               ├─► gnome-screenshot available?
               │      └─► Use gnome-screenshot
               │
               ├─► grim+slurp available?
               │      └─► Use grim/slurp
               │
               └─► Use XDG Portal
```

### Key Files

- `share/shutter/resources/modules/Shutter/Screenshot/Backend.pm` - Session detection and capability checking
- `share/shutter/resources/modules/Shutter/Screenshot/Wayland.pm` - Wayland capture implementations
- `bin/shutter` - Main application with UI integration

## Known Issues

1. **Menu/Tooltip capture**: Not possible on Wayland (compositor limitation)
2. **Include cursor**: May not work with XDG Portal alone
3. **Precise selection**: Portal-based selection uses the portal's own UI
4. **Edit immediately after capture**: Works, but redo/history may have limitations

## Reporting Issues

Please report issues at: https://github.com/shutter-project/shutter/issues

When reporting Wayland-related issues, please include:
1. Output of `echo $XDG_SESSION_TYPE`
2. Output of `perl t/backend_test.pl`
3. Ubuntu version (`lsb_release -a`)
4. GNOME Shell version (`gnome-shell --version`)
5. Whether gnome-screenshot is installed
