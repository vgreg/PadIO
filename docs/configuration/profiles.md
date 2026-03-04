# Profiles & Modes

## Profiles

A profile is a named set of bindings that applies when specific apps are in the foreground.

```json
"profiles": {
  "terminal": {
    "apps": ["com.mitchellh.ghostty", "com.apple.Terminal"],
    "default_mode": "shell",
    "global": {
      "options": { "type": "mode_select" }
    },
    "modes": {
      "shell": { ... },
      "nvim": { ... }
    }
  },
  "default": {
    "apps": [],
    "default_mode": "general",
    "global": {},
    "modes": {
      "general": { ... }
    }
  }
}
```

| Field          | Type     | Description |
|----------------|----------|-------------|
| `apps`         | string[] | Bundle IDs this profile applies to. Empty list = default catch-all profile. |
| `default_mode` | string   | Mode to activate when the profile is first entered. |
| `global`       | object   | Bindings that apply in all modes of this profile. Overridden by top-level `global`. |
| `modes`        | object   | Named modes, each containing button bindings. |

### Profile resolution order

1. First profile whose `apps` list contains the frontmost app's bundle ID.
2. The profile named `"default"` (fallback for unmatched apps).

## Shared Modes

Modes defined in the top-level `shared_modes` object are available to all profiles without redefinition. Any profile can reference a shared mode by name — it works the same as a profile-defined mode.

```json
{
  "shared_modes": {
    "media": {
      "LB":         { "type": "keystroke", "key": "play_pause" },
      "RB":         { "type": "keystroke", "key": "next_track" },
      "dpad_up":    { "type": "keystroke", "key": "volume_up" },
      "dpad_down":  { "type": "keystroke", "key": "volume_down" }
    }
  }
}
```

Now every profile that supports mode switching can switch to `"media"` — the bindings are resolved from `shared_modes` when the active mode name isn't found in the profile's own `modes` dictionary.

If a profile defines a mode with the same name as a shared mode, the profile's mode takes priority.

## Modes

A mode is a flat object mapping button names to action objects:

```json
"shell": {
  "A":          { "type": "keystroke", "key": "return" },
  "dpad_up":    { "type": "keystroke", "key": "up" },
  "dpad_down":  { "type": "keystroke", "key": "down" }
}
```

Each profile can have multiple modes. Only one mode is active at a time. Switch between modes using:

- [`mode_select`](actions.md#mode_select) — opens a picker overlay
- [`prev_mode` / `next_mode`](actions.md#prev_mode-next_mode) — cycle through modes
- [`mode:<name>`](actions.md#modename) — jump directly to a named mode

## Button combos

Hold one button as a modifier to change what another button does. Use the syntax `"<modifier>+<button>"` as a binding key:

```json
"nvim": {
  "dpad_up":     { "type": "keystroke", "key": "k" },
  "dpad_down":   { "type": "keystroke", "key": "j" },
  "X+dpad_up":   { "type": "keystroke", "key": "k", "modifiers": ["ctrl"] },
  "X+dpad_down": { "type": "keystroke", "key": "j", "modifiers": ["ctrl"] }
}
```

In this example, pressing dpad_up sends `k`, but holding X and pressing dpad_up sends `ctrl-k` instead.

Combo keys work in top-level `global`, profile `global`, and mode bindings — anywhere regular button keys work. The modifier button still fires its own action when first pressed; users who want a "pure modifier" button simply don't bind it to any action.

## Binding resolution order

When a button is pressed, PadIO checks combo keys first (if any other buttons are held), then falls back to plain keys:

1. **Combo key in top-level `global`**
2. **Combo key in profile `global`**
3. **Combo key in active mode bindings**
4. **Plain key in top-level `global`**
5. **Plain key in profile `global`**
6. **Plain key in active mode bindings**

If multiple buttons are held simultaneously, PadIO tries them in `ButtonID` order and uses the first match.

This means you can set a button in the top-level `global` to guarantee it always does the same thing, while still allowing per-mode overrides for other buttons.
