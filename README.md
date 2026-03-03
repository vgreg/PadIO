# PadIO

PadIO is a macOS menu bar daemon that maps Xbox (or any MFi/HID) controller inputs to synthetic keyboard events. It runs in the background with no window, reads a JSON config file, and fires keystrokes to whatever app is in the foreground — even when PadIO itself is not.

## Requirements

- macOS 14.0 (Sonoma) or later
- **Accessibility permission** — required to post synthetic keyboard events
- An Xbox Wireless Controller (or any controller recognized by the GameController framework)

## Installation

1. Open `PadIO.xcodeproj` in Xcode.
2. Build and run (⌘R), or archive and export as a release build.
3. On first launch, grant Accessibility access when prompted (or open the menu bar icon → **Grant Accessibility Access**).

## Configuration

PadIO reads its config from:

```
~/.config/padio/config.json
```

The file is **hot-reloaded** — save changes and they take effect immediately without restarting the app.

If the file does not exist, PadIO runs with no bindings (controller input is silently ignored).

---

## Config File Format

### Top-level structure

```json
{
  "trigger_threshold": 0.5,
  "debug_overlay": false,
  "global": { },
  "profiles": { },
  "menus": { }
}
```

| Field               | Type    | Default | Description |
|---------------------|---------|---------|-------------|
| `trigger_threshold` | number  | `0.5`   | Analog trigger press threshold (0–1). Values above this are treated as pressed. |
| `debug_overlay`     | boolean | `false` | Show a floating HUD on every button press displaying the button name and resolved action. Set to `true` during development. |
| `global`            | object  | `{}`    | Button bindings applied to all profiles. These take priority over everything else. |
| `profiles`          | object  | `{}`    | Named profiles, each applying to a set of apps. |
| `menus`             | object  | `{}`    | Named custom menus (see [Custom Menus](#custom-menus)). |

### Profiles

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

**Profile resolution order:**
1. First profile whose `apps` list contains the frontmost app's bundle ID.
2. The profile named `"default"` (fallback for unmatched apps).

**Binding resolution order (highest priority wins):**
1. Top-level `global`
2. Profile `global`
3. Active mode bindings

### Modes

A mode is a flat object mapping button names to action objects:

```json
"shell": {
  "A":          { "type": "keystroke", "key": "return" },
  "dpad_up":    { "type": "keystroke", "key": "up" },
  "dpad_down":  { "type": "keystroke", "key": "down" }
}
```

---

## Action Types

### `keystroke`

Fires a single synthetic key event.

```json
{ "type": "keystroke", "key": "space" }
{ "type": "keystroke", "key": "escape", "modifiers": ["ctrl"] }
{ "type": "keystroke", "key": "k", "modifiers": ["hyper"] }
{ "type": "keystroke", "key": "play_pause" }
```

| Field       | Type     | Required | Description |
|-------------|----------|----------|-------------|
| `key`       | string   | yes      | Key name (see [Key Names](#key-names) below), or a backtick-delimited unicode string (see [Unicode Text](#unicode-text)). |
| `modifiers` | string[] | no       | Modifier keys to hold while pressing (see [Modifiers](#modifiers)). Ignored for unicode text. |

#### Unicode Text

Wrap any unicode text in backticks to inject it directly — bypassing keyboard layout and supporting any character: accents, emoji, arrows, CJK, or multi-character strings.

```json
{ "type": "keystroke", "key": "`é`" }
{ "type": "keystroke", "key": "`🎉`" }
{ "type": "keystroke", "key": "`→`" }
{ "type": "keystroke", "key": "`hello world`" }
```

Escape sequences inside backtick strings:
- `` \` `` → literal backtick
- `\\` → literal backslash

```json
{ "type": "keystroke", "key": "`contains \\` backtick`" }
{ "type": "keystroke", "key": "`backslash: \\\\`" }
```

The `modifiers` field has no effect on unicode text actions.

### `mode_select`

Opens the mode picker overlay. Navigate with dpad up/down, confirm with A or RT, cancel with X or LT.

```json
{ "type": "mode_select" }
```

Typically bound to the `options` button in a profile's `global` section.

### `prev_mode` / `next_mode`

Instantly switch to the previous or next mode in the sorted mode list (wraps around). A brief notification HUD shows the new mode name. No overlay is shown.

```json
{ "type": "prev_mode" }
{ "type": "next_mode" }
```

Useful bound to `LB`/`RB` in a profile's `global` section for quick cycling without opening the picker.

### `mode:<name>`

Switch directly to a named mode without opening the picker. The mode must exist in the current profile.

```json
{ "type": "mode:shell" }
{ "type": "mode:nvim" }
```

### `menu:<name>`

Open a named custom menu overlay (defined in the top-level `menus` object). See [Custom Menus](#custom-menus).

```json
{ "type": "menu:git" }
```

### `keyboard_viewer`

Toggle the macOS Keyboard Viewer floating palette on or off. Does not require Accessibility permission.

```json
{ "type": "keyboard_viewer" }
```

### `next_input_source`

Cycle to the next enabled keyboard input source (language or layout). Wraps around the full list of enabled sources. Does not require Accessibility permission.

```json
{ "type": "next_input_source" }
```

### `left_click` / `right_click`

Emit a left or right mouse click at the current cursor position. Requires Accessibility permission.

```json
{ "type": "left_click" }
{ "type": "right_click" }
```

Useful bound to thumbstick clicks (`L3`, `R3`) alongside axis-mapped stick movement.

### `mouse_move`

Map a joystick or dpad to continuous mouse cursor movement. Used as a **mode binding key** with the axis source name (`left_stick`, `right_stick`, `dpad`) as the key.

```json
"left_stick": {
  "type": "mouse_move",
  "speed": 15
}
```

```json
"left_stick": {
  "type": "mouse_move",
  "x_speed": 20,
  "y_speed": 12,
  "y_inverted": true,
  "modifier": "RB",
  "modifier_speed": 3
}
```

| Field            | Type    | Default | Description |
|------------------|---------|---------|-------------|
| `speed`          | number  | `15`    | Base speed multiplier applied to both axes. |
| `x_speed`        | number  | `speed` | Speed multiplier for the X axis (overrides `speed`). |
| `y_speed`        | number  | `speed` | Speed multiplier for the Y axis (overrides `speed`). |
| `x_inverted`     | boolean | `false` | Invert the horizontal axis. |
| `y_inverted`     | boolean | `false` | Invert the vertical axis. |
| `modifier`       | string  | —       | Button name (e.g. `"RB"`) that, when held, applies `modifier_speed` instead of the base speed. |
| `modifier_speed` | number  | `2.0`   | Speed multiplier used when the `modifier` button is held. |

Axis events are emitted every tick (~60Hz) while the stick is deflected beyond the deadzone (0.1). The cursor movement per tick is `axis_value × speed`.

The `modifier` button acts as a precision/turbo toggle: hold it to switch between the base speed and `modifier_speed`. For example, set `"modifier": "RB", "modifier_speed": 3` to boost speed while holding RB, or use a value below `1.0` for a slow/precision mode.

### `scroll`

Map a joystick or dpad to continuous scroll wheel events. Same parameters as `mouse_move` but controls scrolling instead of cursor position.

```json
"right_stick": {
  "type": "scroll",
  "speed": 3,
  "y_inverted": true
}
```

| Field            | Type    | Default | Description |
|------------------|---------|---------|-------------|
| `speed`          | number  | `3`     | Base scroll speed multiplier applied to both axes. |
| `x_speed`        | number  | `speed` | Speed multiplier for horizontal scroll (overrides `speed`). |
| `y_speed`        | number  | `speed` | Speed multiplier for vertical scroll (overrides `speed`). |
| `x_inverted`     | boolean | `false` | Invert horizontal scroll direction. |
| `y_inverted`     | boolean | `false` | Invert vertical scroll direction. |
| `modifier`       | string  | —       | Button name that, when held, applies `modifier_speed` instead of the base speed. |
| `modifier_speed` | number  | `2.0`   | Speed multiplier used when the `modifier` button is held. |

---

## Axis Source Names

Use these as binding keys alongside button names in any `global` or mode binding dictionary:

| Key            | Source                                           |
|----------------|--------------------------------------------------|
| `left_stick`   | Left thumbstick (analog, -1…+1 per axis)        |
| `right_stick`  | Right thumbstick (analog, -1…+1 per axis)       |
| `dpad`         | D-pad (treated as digital: -1, 0, or +1)        |

> **Note:** When `dpad` is used as an axis source for `mouse_move` or `scroll`, the individual dpad direction buttons (`dpad_up`, `dpad_down`, etc.) should not also be bound in the same mode — they will still fire as buttons.

---

### `sequence`

Fires multiple keystrokes in order, with a configurable delay between each. Useful for terminal prefix sequences (e.g. tmux `ctrl-a` then `n`).

```json
{
  "type": "sequence",
  "steps": [
    { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
    { "type": "keystroke", "key": "n" }
  ],
  "delay": 0.05
}
```

| Field   | Type     | Default | Description |
|---------|----------|---------|-------------|
| `steps` | array    | —       | Ordered list of `keystroke` action objects. |
| `delay` | number   | `0.05`  | Seconds to wait between each step (50ms default). |

---

## Key Names

### Letters

`a` `b` `c` `d` `e` `f` `g` `h` `i` `j` `k` `l` `m`
`n` `o` `p` `q` `r` `s` `t` `u` `v` `w` `x` `y` `z`

### Numbers

`0` `1` `2` `3` `4` `5` `6` `7` `8` `9`

### Special Keys

| Key name        | Key                   |
|-----------------|-----------------------|
| `space`         | Space bar             |
| `return`        | Return / Enter        |
| `enter`         | Return / Enter        |
| `tab`           | Tab                   |
| `escape` / `esc`| Escape                |
| `delete` / `backspace` | Delete (backspace) |
| `forwarddelete` | Forward delete        |

### Arrow & Navigation Keys

| Key name    | Key         |
|-------------|-------------|
| `up`        | Arrow up    |
| `down`      | Arrow down  |
| `left`      | Arrow left  |
| `right`     | Arrow right |
| `home`      | Home        |
| `end`       | End         |
| `pageup`    | Page up     |
| `pagedown`  | Page down   |

### Function Keys

`f1` `f2` `f3` `f4` `f5` `f6` `f7` `f8` `f9` `f10` `f11` `f12`

### Punctuation

`` ` `` `-` `=` `[` `]` `\` `;` `'` `,` `.` `/`

### Media / Special Keys

These use the system media key path (no Accessibility permission required).

| Key name           | Action              |
|--------------------|---------------------|
| `play_pause`       | Play / Pause        |
| `next_track`       | Next track          |
| `prev_track`       | Previous track      |
| `previous_track`   | Previous track      |
| `volume_up`        | Volume up           |
| `volume_down`      | Volume down         |
| `mute`             | Mute                |
| `brightness_up`    | Brightness up       |
| `brightness_down`  | Brightness down     |

---

## Modifiers

| Modifier name       | Keys held                         |
|---------------------|-----------------------------------|
| `cmd` / `command`   | Command (⌘)                      |
| `ctrl` / `control`  | Control (⌃)                      |
| `alt` / `option`    | Option (⌥)                       |
| `shift`             | Shift (⇧)                        |
| `hyper`             | ⌘ + ⌃ + ⌥ + ⇧ (all four)       |
| `meh`               | ⌃ + ⌥ + ⇧ (everything but ⌘)   |

`hyper` and `meh` are useful for binding controller buttons to app-specific shortcuts that won't conflict with standard system shortcuts.

---

## Button Names

| Button name   | Physical button          |
|---------------|--------------------------|
| `A`           | A button                 |
| `B`           | B button                 |
| `X`           | X button                 |
| `Y`           | Y button                 |
| `LB`          | Left bumper              |
| `RB`          | Right bumper             |
| `LT`          | Left trigger             |
| `RT`          | Right trigger            |
| `dpad_up`     | D-pad up                 |
| `dpad_down`   | D-pad down               |
| `dpad_left`   | D-pad left               |
| `dpad_right`  | D-pad right              |
| `L3`          | Left thumbstick click    |
| `R3`          | Right thumbstick click   |
| `menu`        | Menu button (≡)          |
| `options`     | Options / View button    |
| `share`       | Share button (Xbox Elite) |
| `paddle1`–`paddle4` | Paddle buttons (Xbox Elite) |

> **Note:** The `menu` button is reserved for the Help HUD (see below) and cannot be rebound via config.

---

## Custom Menus

Named menus are defined at the top level of the config under `"menus"`. Each menu is an array of `{ label, action }` pairs and is opened via the `menu:<name>` action type.

```json
"menus": {
  "git": [
    { "label": "git status",  "action": { "type": "keystroke", "key": "`git status\n`" } },
    { "label": "git diff",    "action": { "type": "keystroke", "key": "`git diff\n`" } },
    { "label": "git push",    "action": { "type": "keystroke", "key": "`git push\n`" } }
  ]
}
```

Open it from any binding:

```json
"Y": { "type": "menu:git" }
```

**Navigation:**
- **dpad up/down** — move highlight
- **A** or **RT** — select item and execute its action
- **B**, **X**, or **LT** — cancel and close

Menu item actions can be any action type, including another `menu:<name>` for nested menus.

---

## HUDs

### Help HUD (menu button)

Press the **menu (≡)** button at any time to open a floating overlay showing all effective button mappings for the current profile and mode.

- Navigate the list with **dpad up/down**
- Close with **B**, **X**, or **LT** (or press **menu** again)

The Help HUD takes priority over all other button processing while visible.

### Mode Notification

When a mode switch occurs via `prev_mode`, `next_mode`, or `mode:<name>`, a small overlay briefly appears at the top of the screen displaying the new mode name. It auto-dismisses after 1.5 seconds.

### Debug Overlay

When `"debug_overlay": true` is set in the config, a small pill-shaped HUD appears at the bottom of the screen on every button press, showing:
- Top line: button name (e.g. `A`, `dpad_up`)
- Bottom line: resolved action (e.g. `ctrl+a → n`, `media: play_pause`, `no mapping`)

The overlay auto-dismisses after 2 seconds. A new press resets the timer immediately.

Set `"debug_overlay": false` (or omit the field) for production use.

---

## Full Example Config

```json
{
  "trigger_threshold": 0.5,
  "debug_overlay": false,
  "global": {
    "left_stick":  { "type": "mouse_move", "speed": 15, "modifier": "RB", "modifier_speed": 3 },
    "right_stick": { "type": "scroll", "speed": 3, "y_inverted": true },
    "L3":          { "type": "left_click" },
    "R3":          { "type": "right_click" }
  },
  "profiles": {
    "default": {
      "apps": [],
      "default_mode": "general",
      "global": {
        "options": { "type": "mode_select" }
      },
      "modes": {
        "general": {
          "A":          { "type": "keystroke", "key": "space" },
          "B":          { "type": "keystroke", "key": "escape" },
          "dpad_up":    { "type": "keystroke", "key": "up" },
          "dpad_down":  { "type": "keystroke", "key": "down" },
          "dpad_left":  { "type": "keystroke", "key": "left" },
          "dpad_right": { "type": "keystroke", "key": "right" },
          "LB":         { "type": "keystroke", "key": "play_pause" },
          "RB":         { "type": "keystroke", "key": "next_track" }
        }
      }
    },
    "terminal": {
      "apps": ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2"],
      "default_mode": "shell",
      "global": {
        "options": { "type": "mode_select" },
        "LB":      { "type": "prev_mode" },
        "RB":      { "type": "next_mode" }
      },
      "modes": {
        "shell": {
          "A":          { "type": "keystroke", "key": "return" },
          "B":          { "type": "keystroke", "key": "c", "modifiers": ["ctrl"] },
          "X":          { "type": "keystroke", "key": "l", "modifiers": ["ctrl"] },
          "Y":          { "type": "menu:git" },
          "dpad_up":    { "type": "keystroke", "key": "up" },
          "dpad_down":  { "type": "keystroke", "key": "down" },
          "dpad_left":  { "type": "keystroke", "key": "left" },
          "dpad_right": { "type": "keystroke", "key": "right" }
        },
        "nvim": {
          "A":          { "type": "keystroke", "key": "return" },
          "B":          { "type": "keystroke", "key": "escape" },
          "X":          { "type": "keystroke", "key": "u" },
          "Y":          { "type": "keystroke", "key": "r", "modifiers": ["ctrl"] },
          "dpad_up":    { "type": "keystroke", "key": "k" },
          "dpad_down":  { "type": "keystroke", "key": "j" },
          "dpad_left":  { "type": "keystroke", "key": "h" },
          "dpad_right": { "type": "keystroke", "key": "l" }
        },
        "tmux": {
          "A": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "return" }
            ],
            "delay": 0.05
          },
          "dpad_up": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "up" }
            ]
          },
          "dpad_down": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "down" }
            ]
          },
          "dpad_left": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "left" }
            ]
          },
          "dpad_right": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "right" }
            ]
          }
        }
      }
    }
  },
  "menus": {
    "git": [
      { "label": "git status",    "action": { "type": "keystroke", "key": "`git status\n`" } },
      { "label": "git diff",      "action": { "type": "keystroke", "key": "`git diff\n`" } },
      { "label": "git log",       "action": { "type": "keystroke", "key": "`git log --oneline -20\n`" } },
      { "label": "git pull",      "action": { "type": "keystroke", "key": "`git pull\n`" } },
      { "label": "git push",      "action": { "type": "keystroke", "key": "`git push\n`" } },
      { "label": "git stash",     "action": { "type": "keystroke", "key": "`git stash\n`" } },
      { "label": "git stash pop", "action": { "type": "keystroke", "key": "`git stash pop\n`" } }
    ]
  }
}
```

---

## Permissions

PadIO requires **Accessibility** permission to post synthetic keyboard events to other applications.

- Open the **PadIO menu bar icon** → **Grant Accessibility Access** to trigger the system prompt.
- Or go to **System Settings → Privacy & Security → Accessibility** and add PadIO manually.

The following action types do **not** require Accessibility permission and work unconditionally:
- Media key events (`play_pause`, `next_track`, `volume_up`, etc.)
- `keyboard_viewer`
- `next_input_source`
