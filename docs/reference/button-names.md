# Button Names

These are the valid button names for use as binding keys in any `global` or mode binding dictionary.

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

!!! note
    The `menu` button is reserved for the Help HUD and cannot be rebound via config.

## Button combos

Any button can be used as a modifier by holding it while pressing another button. Use `"<modifier>+<button>"` as the binding key:

```json
"X+dpad_up": { "type": "keystroke", "key": "k", "modifiers": ["ctrl"] }
```

This fires when X is held and dpad_up is pressed. See [Profiles & Modes](../configuration/profiles.md#button-combos) for full details.

See [Controller Compatibility](controllers.md) for how these map to physical buttons on different controllers.
