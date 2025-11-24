# Shutter - Screenshot Tool

Shutter is a feature-rich screenshot program for Linux-based operating systems. It allows you to take a screenshot of a specific area, window, your whole screen, or even a website - apply different effects to it, draw on it to highlight points, and then upload to an image hosting site, all within one window.

## Features

- **Multiple capture modes**: Selection, Window, Full Screen, Menu, Tooltip, Web
- **Built-in editor**: Draw, annotate, add shapes, text, arrows, and more
- **Effects and plugins**: Apply various effects to screenshots
- **Upload support**: Upload directly to image hosting services
- **Session management**: Keep track of all screenshots taken during a session

## Ubuntu 22.04 / Wayland Support

Shutter now includes enhanced support for Ubuntu 22.04 and Wayland sessions:

- **Automatic detection**: Shutter detects your session type (Wayland or X11) on startup
- **XDG Desktop Portal**: Uses the portal API for screenshot capture on Wayland
- **gnome-screenshot fallback**: Supports gnome-screenshot for additional features
- **grim/slurp support**: Works with wlroots-based compositors (Sway, etc.)

### Feature Availability

| Feature | X11 | Wayland |
|---------|-----|---------|
| Full Screen | Yes | Yes |
| Selection | Yes | Yes* |
| Window | Yes | Partial** |
| Menu/Tooltip | Yes | No*** |

\* Selection on Wayland uses gnome-screenshot or XDG Portal UI
\** Window capture requires gnome-screenshot on Wayland
\*** Menu/Tooltip capture not possible due to Wayland security model

For detailed information, see [docs/UBUNTU_22.04_WAYLAND.md](docs/UBUNTU_22.04_WAYLAND.md).

## Installation

### Ubuntu 22.04

```bash
# Required dependencies
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

# Recommended for better Wayland support
sudo apt install gnome-screenshot
```

### From Source

```bash
git clone https://github.com/shutter-project/shutter.git
cd shutter
./bin/shutter
```

## Usage

### Basic Usage

```bash
# Launch GUI
shutter

# Take a selection screenshot
shutter --select

# Take a full screen screenshot
shutter --full

# Take a window screenshot
shutter --window
```

### Command Line Options

```
--select, -s      Take a selection screenshot
--full, -f        Take a full screen screenshot
--window, -w      Take a window screenshot
--active, -a      Take an active window screenshot
--delay=N, -d N   Wait N seconds before taking screenshot
--help, -h        Show help
--version         Show version
```

## Testing

Run the backend test to verify your setup:

```bash
perl t/backend_test.pl
```

## Development

### Architecture

```
bin/
  shutter              - Main application script

share/shutter/resources/modules/Shutter/
  Screenshot/
    Backend.pm         - Session detection and capability checking
    Wayland.pm         - Wayland capture implementations (XDG Portal, gnome-screenshot, grim)
    Main.pm            - Base screenshot class
    SelectorAdvanced.pm - Interactive selection (X11)
    Window.pm          - Window capture (X11)
    Workspace.pm       - Full screen/workspace capture (X11)
    ...
  App/
    Common.pm          - Application common utilities
    Toolbar.pm         - Toolbar implementation
    Menu.pm            - Menu implementation
    ...
  Draw/
    DrawingTool.pm     - Image editor
  Pixbuf/
    Save.pm            - Image saving
    Load.pm            - Image loading
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

Shutter is free software released under the GNU General Public License v3.0.

## Links

- **Homepage**: https://shutter-project.org/
- **Repository**: https://github.com/shutter-project/shutter
- **Issues**: https://github.com/shutter-project/shutter/issues
- **Wayland Support Discussion**: https://github.com/shutter-project/shutter/issues/187
