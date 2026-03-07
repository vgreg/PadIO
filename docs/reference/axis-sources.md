# Axis Sources

Use these as binding keys alongside button names in any `global` or mode binding dictionary. They are used with the [`mouse_move`](../configuration/actions.md#mouse_move) and [`scroll`](../configuration/actions.md#scroll) action types.

| Key            | Source                                           |
|----------------|--------------------------------------------------|
| `left_stick`   | Left thumbstick (analog, -1…+1 per axis)        |
| `right_stick`  | Right thumbstick (analog, -1…+1 per axis)       |
| `dpad`         | D-pad (treated as digital: -1, 0, or +1)        |

Joystick axes use a **quadratic response curve** (`value × |value|`) after the deadzone. This preserves sign, gives fine control near the center, and amplifies large deflections for fast movement at full tilt.

!!! note
    When `dpad` is used as an axis source for `mouse_move` or `scroll`, the individual dpad direction buttons (`dpad_up`, `dpad_down`, etc.) should not also be bound in the same mode — they will still fire as buttons.
