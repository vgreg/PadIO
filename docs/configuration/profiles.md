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

## Binding resolution order

When a button is pressed, PadIO resolves the action using this priority (highest wins):

1. **Top-level `global`** — always wins
2. **Profile `global`** — profile-wide bindings
3. **Active mode bindings** — the current mode's mappings

This means you can set a button in the top-level `global` to guarantee it always does the same thing, while still allowing per-mode overrides for other buttons.
