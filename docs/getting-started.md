# Getting Started

## Create a config file

PadIO reads its config from:

```
~/.config/padio/config.json
```

Create the directory and file:

```bash
mkdir -p ~/.config/padio
touch ~/.config/padio/config.json
```

## Minimal example

Start with a simple config that maps face buttons and dpad:

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
          "dpad_down": { "type": "keystroke", "key": "down" },
          "dpad_left": { "type": "keystroke", "key": "left" },
          "dpad_right": { "type": "keystroke", "key": "right" }
        }
      }
    }
  }
}
```

Save the file, and the bindings take effect immediately — no restart needed.

## Hot-reload

The config file is **hot-reloaded**. Save changes and they take effect instantly. If the file contains invalid JSON, PadIO keeps the previous valid config and logs the parse error.

## Help HUD

Press the **menu (≡)** button on your controller at any time to open a floating overlay showing all effective button mappings for the current profile and mode. This is the quickest way to check what each button does.

- Navigate with **dpad up/down**
- Close with **B**, **X**, or **LT** (or press **menu** again)

## Next steps

- [Configuration overview](configuration/index.md) — understand the config structure
- [Profiles & modes](configuration/profiles.md) — set up per-app profiles
- [Actions](configuration/actions.md) — all available action types
- [Example config](example-config.md) — a complete annotated config
