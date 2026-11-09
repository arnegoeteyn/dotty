#!/usr/bin/env bash
# Cinnamon (X11) keybinding tweaks so wezterm can use Super.
# Frees Super shortcuts that the desktop grabs. Run once; persists via dconf.

set -euo pipefail

# Stop a lone Super tap from opening the Mint menu.
gsettings set com.linuxmint.mintmenu hot-key ''

# Super+l: looking glass (Cinnamon).
gsettings set org.cinnamon.desktop.keybindings looking-glass-keybinding '[]'

# Super+d: show desktop.
gsettings set org.cinnamon.desktop.keybindings.wm show-desktop '[]'

# Super+p: switch monitor (keep the XF86Display key).
gsettings set org.cinnamon.desktop.keybindings.wm switch-monitor "['XF86Display']"

# Super+h: minimize.
gsettings set org.gnome.desktop.wm.keybindings minimize '[]'

# Super+l: screen lock moves to Ctrl+Alt+l.
gsettings set org.gnome.settings-daemon.plugins.media-keys screensaver "['<Control><Alt>l']"
