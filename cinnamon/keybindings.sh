#!/usr/bin/env bash
# Cinnamon (X11) keybinding tweaks so wezterm can use Super.
# Removes every <Super> binding from the desktop's keybinding schemas, keeping
# any non-Super entries (e.g. XF86 keys). Run once; persists via dconf.

set -euo pipefail

# Stop a lone Super tap from opening the Mint menu.
gsettings set com.linuxmint.mintmenu hot-key ''

# Super+l screen lock moves to Ctrl+Alt+l.
gsettings set org.gnome.settings-daemon.plugins.media-keys screensaver "['<Control><Alt>l']"

# Super+p: switch monitor (keep the XF86Display key).
gsettings set org.cinnamon.desktop.keybindings.wm switch-monitor "['XF86Display']"

# Drop <Super> entries from a list-valued key, keeping the rest.
strip_super() {
    local schema=$1 key=$2
    gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key" || return 0

    local current filtered
    current=$(gsettings get "$schema" "$key")
    filtered=$(python3 - "$current" <<'PY'
import ast, sys
raw = sys.argv[1].removeprefix("@as ").strip()
items = [i for i in ast.literal_eval(raw) if "<Super>" not in i]
print("[" + ", ".join(repr(i) for i in items) + "]")
PY
)
    if [[ "$filtered" != "${current#@as }" ]]; then
        gsettings set "$schema" "$key" "$filtered"
        echo "cleared Super in $schema $key: $current -> $filtered"
    fi
}

schemas_keys=(
    org.cinnamon.desktop.keybindings:looking-glass-keybinding
    org.cinnamon.desktop.keybindings:magnifier-zoom-in
    org.cinnamon.desktop.keybindings:magnifier-zoom-out
    org.cinnamon.desktop.keybindings:magnifier-zoom-reset
    org.cinnamon.desktop.keybindings:show-desklets
    org.cinnamon.desktop.keybindings.wm:show-desktop
    org.cinnamon.desktop.keybindings.wm:move-to-monitor-down
    org.cinnamon.desktop.keybindings.wm:move-to-monitor-left
    org.cinnamon.desktop.keybindings.wm:move-to-monitor-right
    org.cinnamon.desktop.keybindings.wm:move-to-monitor-up
    org.cinnamon.desktop.keybindings.wm:push-tile-down
    org.cinnamon.desktop.keybindings.wm:push-tile-left
    org.cinnamon.desktop.keybindings.wm:push-tile-right
    org.cinnamon.desktop.keybindings.wm:push-tile-up
    org.cinnamon.desktop.keybindings.wm:switch-input-source
    org.cinnamon.desktop.keybindings.wm:switch-input-source-backward
    org.cinnamon.desktop.keybindings.media-keys:home
    org.cinnamon.desktop.keybindings.media-keys:screenreader
    org.cinnamon.desktop.keybindings.media-keys:video-rotation-lock
    org.cinnamon.muffin.wayland.keybindings:restore-shortcuts
    org.gnome.desktop.wm.keybindings:maximize
    org.gnome.desktop.wm.keybindings:unmaximize
    org.gnome.desktop.wm.keybindings:minimize
    org.gnome.desktop.wm.keybindings:move-to-monitor-down
    org.gnome.desktop.wm.keybindings:move-to-monitor-left
    org.gnome.desktop.wm.keybindings:move-to-monitor-right
    org.gnome.desktop.wm.keybindings:move-to-monitor-up
    org.gnome.desktop.wm.keybindings:move-to-workspace-1
    org.gnome.desktop.wm.keybindings:move-to-workspace-last
    org.gnome.desktop.wm.keybindings:move-to-workspace-left
    org.gnome.desktop.wm.keybindings:move-to-workspace-right
    org.gnome.desktop.wm.keybindings:switch-applications
    org.gnome.desktop.wm.keybindings:switch-applications-backward
    org.gnome.desktop.wm.keybindings:switch-group
    org.gnome.desktop.wm.keybindings:switch-group-backward
    org.gnome.desktop.wm.keybindings:switch-input-source
    org.gnome.desktop.wm.keybindings:switch-input-source-backward
    org.gnome.desktop.wm.keybindings:switch-to-workspace-1
    org.gnome.desktop.wm.keybindings:switch-to-workspace-last
    org.gnome.desktop.wm.keybindings:switch-to-workspace-left
    org.gnome.desktop.wm.keybindings:switch-to-workspace-right
    org.gnome.metacity.keybindings:toggle-tiled-left
    org.gnome.metacity.keybindings:toggle-tiled-right
    org.gnome.settings-daemon.plugins.media-keys:help
    org.gnome.settings-daemon.plugins.media-keys:magnifier
    org.gnome.settings-daemon.plugins.media-keys:magnifier-zoom-in
    org.gnome.settings-daemon.plugins.media-keys:magnifier-zoom-out
    org.gnome.settings-daemon.plugins.media-keys:rotate-video-lock-static
    org.gnome.settings-daemon.plugins.media-keys:screenreader
    org.gnome.settings-daemon.plugins.media-keys:touchpad-toggle-static
    org.freedesktop.ibus.panel.emoji:hotkey
)

for entry in "${schemas_keys[@]}"; do
    strip_super "${entry%%:*}" "${entry#*:}"
done

# Super+1..9 (and Super+Shift+1..9) are hardcoded in the grouped-window-list
# applet, not gsettings. Turn off its "super-num-hotkeys" option in every instance.
for cfg in "$HOME"/.config/cinnamon/spices/grouped-window-list@cinnamon.org/*.json; do
    [[ -f "$cfg" ]] || continue
    python3 - "$cfg" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
if data.get("super-num-hotkeys", {}).get("value") is True:
    data["super-num-hotkeys"]["value"] = False
    with open(path, "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    print(f"disabled super-num-hotkeys in {path}")
PY
done
