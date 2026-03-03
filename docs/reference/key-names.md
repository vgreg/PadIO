# Key Names

These are the valid values for the `key` field in [`keystroke`](../configuration/actions.md#keystroke) actions.

## Letters

`a` `b` `c` `d` `e` `f` `g` `h` `i` `j` `k` `l` `m`
`n` `o` `p` `q` `r` `s` `t` `u` `v` `w` `x` `y` `z`

## Numbers

`0` `1` `2` `3` `4` `5` `6` `7` `8` `9`

## Special keys

| Key name        | Key                   |
|-----------------|-----------------------|
| `space`         | Space bar             |
| `return`        | Return / Enter        |
| `enter`         | Return / Enter        |
| `tab`           | Tab                   |
| `escape` / `esc`| Escape                |
| `delete` / `backspace` | Delete (backspace) |
| `forwarddelete` | Forward delete        |

## Arrow & navigation keys

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

## Function keys

`f1` `f2` `f3` `f4` `f5` `f6` `f7` `f8` `f9` `f10` `f11` `f12`

## Punctuation

`` ` `` `-` `=` `[` `]` `\` `;` `'` `,` `.` `/`

## Media / special keys

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

## System action keys

These are standalone action types (not used as `key` values inside a `keystroke` action — use their own `type` instead). No Accessibility permission required.

| Action type          | Description                                                  |
|----------------------|--------------------------------------------------------------|
| `keyboard_viewer`    | Toggle the macOS Keyboard Viewer floating palette on or off. |
| `next_input_source`  | Cycle to the next enabled keyboard input source (language/layout). |
