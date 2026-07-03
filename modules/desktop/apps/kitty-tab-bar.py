# lualine-style status bar for kitty.
#
# Shipped into the kitty wrapper by modules/desktop/apps/kitty.nix as
# `tab_bar.py` (kitty loads it because the wrapper points
# KITTY_CONFIG_DIRECTORY at the generated config dir and sets
# `tab_bar_style custom`).
#
#   Left  : powerline tab titles (index: title)
#   Right : git branch + battery + clock, refreshed on a timer
import os
from datetime import datetime

from kitty.fast_data_types import add_timer, get_boss, wcswidth
from kitty.tab_bar import as_rgb, draw_tab_with_powerline
from kitty.utils import color_as_int

REFRESH_SECONDS = 2.0
GIT_GLYPH = "\ue0a0"  # powerline branch symbol (present in Nerd Fonts)
LEADER_LAMP_BG = 0xed8796  # Catppuccin "red" accent, matches the wezterm lamp


def _read(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return None


def _battery():
    base = "/sys/class/power_supply"
    try:
        names = sorted(n for n in os.listdir(base) if n.startswith("BAT"))
    except OSError:
        return ""
    for name in names:
        cap = _read(os.path.join(base, name, "capacity"))
        if cap is None:
            continue
        status = _read(os.path.join(base, name, "status")) or ""
        mark = "+" if status == "Charging" else ""
        return mark + cap + "%"
    return ""


def _git_branch(cwd):
    if not cwd:
        return ""
    ref_prefix = "ref: refs/heads/"
    d = cwd
    try:
        while True:
            head = os.path.join(d, ".git", "HEAD")
            if os.path.isfile(head):
                data = _read(head) or ""
                if data.startswith(ref_prefix):
                    return data[len(ref_prefix):]
                return data[:7]  # detached HEAD -> short sha
            parent = os.path.dirname(d)
            if parent == d:
                return ""
            d = parent
    except OSError:
        return ""


def _active_cwd():
    try:
        w = get_boss().active_window
        return w.cwd_of_child if w else None
    except Exception:
        return None


def _keyboard_mode():
    # Name of the active modal keymap ("leader", "resize", ...) or "" at root.
    try:
        return get_boss().mappings.current_keyboard_mode_name or ""
    except Exception:
        return ""


def _right_text():
    segs = []
    branch = _git_branch(_active_cwd())
    if branch:
        segs.append(" " + GIT_GLYPH + " " + branch + " ")
    bat = _battery()
    if bat:
        segs.append(" " + bat + " ")
    segs.append(datetime.now().strftime(" %a %b %d  %H:%M "))
    return "".join(segs)


def _draw_right(draw_data, screen):
    mode = _keyboard_mode()
    mode_seg = (" " + mode.upper() + " ") if mode else ""
    rest = _right_text()
    x = screen.columns - wcswidth(mode_seg) - wcswidth(rest)
    if x <= screen.cursor.x:
        return
    screen.cursor.x = x
    if mode_seg:
        # LEADER lamp: accent background, matches the old wezterm status lamp.
        screen.cursor.fg = as_rgb(color_as_int(draw_data.default_bg))
        screen.cursor.bg = as_rgb(LEADER_LAMP_BG)
        screen.draw(mode_seg)
    screen.cursor.fg = as_rgb(color_as_int(draw_data.inactive_fg))
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    screen.draw(rest)


def draw_tab(draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data):
    end = draw_tab_with_powerline(
        draw_data, screen, tab, before, max_tab_length, index, is_last, extra_data
    )
    if is_last:
        _draw_right(draw_data, screen)
    return end


def _refresh(timer_id):
    try:
        for tm in get_boss().all_tab_managers:
            tm.mark_tab_bar_dirty()
    except Exception:
        pass


add_timer(_refresh, REFRESH_SECONDS, True)
