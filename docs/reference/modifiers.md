# Modifiers

Modifiers are specified in the `modifiers` array of a [`keystroke`](../configuration/actions.md#keystroke) action.

| Modifier name       | Keys held                         |
|---------------------|-----------------------------------|
| `cmd` / `command`   | Command (⌘)                      |
| `ctrl` / `control`  | Control (⌃)                      |
| `alt` / `option`    | Option (⌥)                       |
| `shift`             | Shift (⇧)                        |
| `hyper`             | ⌘ + ⌃ + ⌥ + ⇧ (all four)       |
| `meh`               | ⌃ + ⌥ + ⇧ (everything but ⌘)   |
| `globe` / `fn`      | Globe / Fn (🌐)                  |

## Usage

```json
{ "type": "keystroke", "key": "k", "modifiers": ["hyper"] }
{ "type": "keystroke", "key": "a", "modifiers": ["ctrl", "shift"] }
```

`hyper` and `meh` are useful for binding controller buttons to app-specific shortcuts that won't conflict with standard system shortcuts.
