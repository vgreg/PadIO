# Actions

Every binding maps a button (or axis) to an action object. The `type` field determines the action.

## `keystroke`

Fires a single synthetic key event.

```json
{ "type": "keystroke", "key": "space" }
{ "type": "keystroke", "key": "escape", "modifiers": ["ctrl"] }
{ "type": "keystroke", "key": "k", "modifiers": ["hyper"] }
{ "type": "keystroke", "key": "play_pause" }
```

| Field       | Type     | Required | Description |
|-------------|----------|----------|-------------|
| `key`       | string   | yes      | Key name (see [Key Names](../reference/key-names.md)), or a backtick-delimited unicode string (see below). |
| `modifiers` | string[] | no       | Modifier keys to hold while pressing (see [Modifiers](../reference/modifiers.md)). Ignored for unicode text. |

### Unicode text

Wrap any unicode text in backticks to inject it directly — bypassing keyboard layout and supporting any character: accents, emoji, arrows, CJK, or multi-character strings.

```json
{ "type": "keystroke", "key": "`é`" }
{ "type": "keystroke", "key": "`🎉`" }
{ "type": "keystroke", "key": "`→`" }
{ "type": "keystroke", "key": "`hello world`" }
```

Escape sequences inside backtick strings:

- `` \` `` — literal backtick
- `\\` — literal backslash

```json
{ "type": "keystroke", "key": "`contains \\` backtick`" }
{ "type": "keystroke", "key": "`backslash: \\\\`" }
```

The `modifiers` field has no effect on unicode text actions.

## `sequence`

Fires multiple keystrokes in order, with a configurable delay between each. Useful for terminal prefix sequences (e.g., tmux `ctrl-a` then `n`).

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

## `mode_select`

Opens the mode picker overlay. Navigate with dpad up/down, confirm with A or RT, cancel with X or LT.

```json
{ "type": "mode_select" }
```

Typically bound to the `options` button in a profile's `global` section.

## `prev_mode` / `next_mode`

Instantly switch to the previous or next mode in the sorted mode list (wraps around). A brief notification HUD shows the new mode name. No overlay is shown.

```json
{ "type": "prev_mode" }
{ "type": "next_mode" }
```

Useful bound to `LB`/`RB` in a profile's `global` section for quick cycling without opening the picker.

## `mode:<name>`

Switch directly to a named mode without opening the picker. The mode must exist in the current profile.

```json
{ "type": "mode:shell" }
{ "type": "mode:nvim" }
```

## `menu`

Open a named custom menu overlay (defined in the top-level `menus` object). See [Custom Menus](menus.md).

```json
{ "type": "menu", "name": "git" }
```

| Field  | Type   | Required | Description |
|--------|--------|----------|-------------|
| `name` | string | yes      | Name of the menu (must match a key in the top-level `menus` object). |

The legacy syntax `"type": "menu:git"` is still supported for backward compatibility.

## `alias`

Reference a reusable action defined in the top-level `aliases` object.

```json
{ "type": "alias", "name": "tmux_leader" }
```

| Field  | Type   | Required | Description |
|--------|--------|----------|-------------|
| `name` | string | yes      | Name of the alias (must match a key in the top-level `aliases` object). |

Define aliases at the top level of your config:

```json
{
  "aliases": {
    "tmux_leader": { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
    "save":        { "type": "keystroke", "key": "s", "modifiers": ["cmd"] }
  }
}
```

Aliases cannot chain — an alias cannot reference another alias.

## `left_click` / `right_click`

Emit a left or right mouse click at the current cursor position. Requires Accessibility permission.

```json
{ "type": "left_click" }
{ "type": "right_click" }
```

Useful bound to thumbstick clicks (`L3`, `R3`) alongside axis-mapped stick movement.

## `left_click_hold` / `right_click_hold`

Hold a mouse button down (for drag operations). Used as hold actions — see [Press vs Hold](#press-vs-hold) below.

```json
{ "type": "left_click_hold" }
{ "type": "right_click_hold" }
```

## `mouse_move`

Map a joystick or dpad to continuous mouse cursor movement. Used as a binding with the [axis source name](../reference/axis-sources.md) as the key.

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

## `scroll`

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

## `keyboard_viewer`

Toggle the macOS Keyboard Viewer floating palette on or off. Does not require Accessibility permission.

```json
{ "type": "keyboard_viewer" }
```

## `next_input_source`

Cycle to the next enabled keyboard input source (language or layout). Wraps around the full list of enabled sources. Does not require Accessibility permission.

```json
{ "type": "next_input_source" }
```

## `rumble`

Fire a one-shot haptic rumble on all connected controllers. Has no effect on controllers that don't support haptics (no error is raised).

```json
{ "type": "rumble" }
{ "type": "rumble", "intensity": 0.8, "delay": 0.3, "sharpness": 0.5 }
```

| Field       | Type   | Default | Description |
|-------------|--------|---------|-------------|
| `intensity` | number | `0.5`   | Motor strength (0.0–1.0). |
| `sharpness` | number | `0.3`   | Haptic sharpness (0.0–1.0). Higher = crisper, lower = softer buzz. |
| `delay`     | number | `0.2`   | Duration of the rumble in seconds. |

Does not require Accessibility permission.

## Press vs Hold

Any action can distinguish between a quick **tap** and a **hold** by adding a `hold` field. When present, the button enters a state machine:

- **Press:** Starts tracking. No action fires immediately.
- **Still held after 300ms:** Fires the hold action. For `left_click_hold` / `right_click_hold`, emits mouse-down. For keystrokes, emits key-down only.
- **Release before 300ms:** Fires the original (tap) action.
- **Release after hold:** Fires the release counterpart (mouse-up / key-up).
- **No `hold` field:** Existing behavior — action fires immediately on press.

```json
"L3": {
  "type": "left_click",
  "hold": { "type": "left_click_hold" }
}
```

In this example, tapping L3 performs a click. Holding L3 holds the left mouse button down for dragging — moving the stick while holding L3 emits drag events instead of regular mouse-move events. Releasing L3 releases the mouse button.

Keystroke hold example — hold to keep a modifier pressed:

```json
"A": {
  "type": "keystroke", "key": "space",
  "hold": { "type": "keystroke", "key": "shift" }
}
```

Tapping A sends space. Holding A holds shift down until released.
