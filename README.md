# PadIO

PadIO is a macOS menu bar daemon that maps game controller inputs to synthetic keyboard events, mouse movement, and more. It runs in the background with no window, reads a JSON config file, and fires keystrokes to whatever app is in the foreground — even when PadIO itself is not. Works with Xbox, PlayStation (DualShock 4, DualSense), Nintendo Switch Pro, and any MFi controller recognized by macOS.

**[Full documentation →](https://www.vincentgregoire.com/PadIO)**

## Who is it for?

PadIO is for users who want **maximum control** over their controller mappings. It's config-file driven and designed for power users who want to define exactly what every button does — including multi-keystroke sequences (e.g., tmux prefix commands), per-app profiles, mode switching, and custom menus.

If you're looking for a friendlier GUI-based controller remapper, search "Game Controller" on the Mac App Store — there are several good options.

## Features

- **Keystroke emission** — any key, any modifier combo, including `hyper` and `meh`
- **Unicode text injection** — emoji, accented characters, CJK, multi-character strings
- **Multi-step sequences** — fire keystroke chains with configurable delay (e.g., tmux prefix)
- **Mouse & scroll** — map sticks/dpad to cursor movement and scroll wheel with speed modifiers
- **Button combos** — hold a modifier button to change what other buttons do (e.g., X+dpad_up)
- **Per-app profiles** — automatic profile switching based on the frontmost application
- **Modes** — multiple binding sets per profile, switchable via picker, cycling, or direct jump
- **Custom menus** — define popup menus with labeled items that trigger any action
- **Haptic feedback** — rumble on system beep, notifications, or on-demand from any binding
- **Media keys** — play/pause, track skip, volume, brightness (no Accessibility permission needed)
- **Hot-reload** — save the config file and changes take effect instantly
- **Help HUD** — press the menu button anytime to see all current bindings
- **Debug overlay** — optional HUD showing every button press and its resolved action

## Installation

### Homebrew (recommended)

```bash
brew install --cask vgreg/tap/padio
```

### Build from source

1. Clone the repo and open `PadIO.xcodeproj` in Xcode.
2. Build and run (⌘R), or archive and export a release build.

See the [Installation guide](https://www.vincentgregoire.com/PadIO/installation/) for details.

## Quick start

Create `~/.config/padio/config.json`:

```json
{
  "profiles": {
    "default": {
      "apps": [],
      "default_mode": "general",
      "modes": {
        "general": {
          "A": { "type": "keystroke", "key": "space" },
          "B": { "type": "keystroke", "key": "escape" },
          "dpad_up": { "type": "keystroke", "key": "up" },
          "dpad_down": { "type": "keystroke", "key": "down" }
        }
      }
    }
  }
}
```

Launch PadIO and grant Accessibility access when prompted. The config file is hot-reloaded — save changes and they take effect immediately.

See the [Getting Started guide](https://www.vincentgregoire.com/PadIO/getting-started/) and the [full example config](https://www.vincentgregoire.com/PadIO/example-config/) for more.

## Requirements

- macOS 14.0 (Sonoma) or later
- **Accessibility permission** — required to post synthetic keyboard events
- A game controller recognized by macOS (Xbox, PlayStation, Nintendo Switch Pro, or any MFi controller)

## License

[MIT](LICENSE)
