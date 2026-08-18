# Configuration Overview

PadIO reads its config from `~/.config/padio/config.json`. The file is hot-reloaded — save changes and they take effect immediately.

If the file does not exist, PadIO runs with no bindings (controller input is silently ignored).

## Top-level structure

```json
{
  "trigger_threshold": 0.5,
  "debug_overlay": false,
  "menu_style": "list",
  "hud_zoom": 1.0,
  "aliases": { },
  "shared_modes": { },
  "hidden_modes": [ ],
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
| `menu_style`        | string  | `"list"` | Default presentation for custom menus — `"list"` or `"wheel"`. Individual menus can override it (see [Custom Menus](menus.md)). |
| `hud_zoom`          | number  | `1.0`   | Uniform scale for every HUD. Clamped to 0.75–3.0 (see [HUDs](../huds.md)). |
| `aliases`           | object  | omitted | Reusable action definitions, referenced by `{ "type": "alias", "name": "<key>" }`. |
| `shared_modes`      | object  | omitted | Modes available to every profile by name (see [Profiles & Modes](profiles.md)). |
| `hidden_modes`      | array   | `[]`    | Mode names hidden from the mode picker across all profiles. They stay reachable via `mode:<name>`, context modes, and `default_mode`. |
| `global`            | object  | `{}`    | Button bindings applied to all profiles. These take priority over everything else. |
| `profiles`          | object  | `{}`    | Named profiles, each applying to a set of apps. |
| `menus`             | object  | `{}`    | Named custom menus (see [Custom Menus](menus.md)). |
| `haptics`           | object  | omitted | Optional haptic/rumble triggers for system events (see [Haptics](haptics.md)). |

## What goes where

- **`global`** — bindings that apply everywhere, regardless of profile or mode. Use this for things like mouse movement on the sticks or click on thumbstick press.
- **`profiles`** — per-app binding sets. Each profile has its own modes. See [Profiles & Modes](profiles.md).
- **`menus`** — popup menus that can be opened from any binding. See [Custom Menus](menus.md).
- **`haptics`** — rumble triggers for system events (beep, notifications). See [Haptics](haptics.md).
- **`menu_style` / `hud_zoom`** — appearance of the floating overlays. `hud_zoom` scales every HUD at once, which is useful when driving PadIO from across the room.
