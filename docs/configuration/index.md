# Configuration Overview

PadIO reads its config from `~/.config/padio/config.json`. The file is hot-reloaded — save changes and they take effect immediately.

If the file does not exist, PadIO runs with no bindings (controller input is silently ignored).

## Top-level structure

```json
{
  "trigger_threshold": 0.5,
  "debug_overlay": false,
  "global": { },
  "profiles": { },
  "menus": { },
  "haptics": { }
}
```

| Field               | Type    | Default | Description |
|---------------------|---------|---------|-------------|
| `trigger_threshold` | number  | `0.5`   | Analog trigger press threshold (0–1). Values above this are treated as pressed. |
| `debug_overlay`     | boolean | `false` | Show a floating HUD on every button press displaying the button name and resolved action. Set to `true` during development. |
| `global`            | object  | `{}`    | Button bindings applied to all profiles. These take priority over everything else. |
| `profiles`          | object  | `{}`    | Named profiles, each applying to a set of apps. |
| `menus`             | object  | `{}`    | Named custom menus (see [Custom Menus](menus.md)). |
| `haptics`           | object  | omitted | Optional haptic/rumble triggers for system events (see [Haptics](haptics.md)). |

## What goes where

- **`global`** — bindings that apply everywhere, regardless of profile or mode. Use this for things like mouse movement on the sticks or click on thumbstick press.
- **`profiles`** — per-app binding sets. Each profile has its own modes. See [Profiles & Modes](profiles.md).
- **`menus`** — popup menus that can be opened from any binding. See [Custom Menus](menus.md).
- **`haptics`** — rumble triggers for system events (beep, notifications). See [Haptics](haptics.md).
