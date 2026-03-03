# Controller Compatibility

PadIO uses Apple's **GameController framework**, which abstracts all connected controllers behind a unified `GCExtendedGamepad` interface. Any controller macOS recognizes will work.

## Button name mapping by controller

| PadIO name | Xbox              | PlayStation       | Nintendo Switch Pro |
|------------|-------------------|-------------------|---------------------|
| `A`        | A                 | Cross (✕)         | B                   |
| `B`        | B                 | Circle (○)        | A                   |
| `X`        | X                 | Square (□)        | Y                   |
| `Y`        | Y                 | Triangle (△)      | X                   |
| `LB`       | Left Bumper       | L1                | L                   |
| `RB`       | Right Bumper      | R1                | R                   |
| `LT`       | Left Trigger      | L2                | ZL                  |
| `RT`       | Right Trigger     | R2                | ZR                  |
| `L3`       | Left Stick click  | L3                | Left Stick click    |
| `R3`       | Right Stick click | R3                | Right Stick click   |
| `options`  | View / Back       | Create            | −                   |
| `menu`     | Menu (≡)          | Options           | +                   |

!!! note
    The `menu` button is reserved for the Help HUD and cannot be rebound.

## Pairing controllers with macOS

- **Xbox**: Bluetooth pairing via System Settings → Bluetooth. USB also works.
- **DualShock 4 / DualSense**: Native support on macOS 12+. Hold PS + Share (DS4) or PS + Create (DualSense) to enter pairing mode, then pair via System Settings → Bluetooth.
- **Nintendo Switch Pro**: Pair via System Settings → Bluetooth (hold the sync button on top of the controller).

## Haptic feedback (rumble) support

Haptic feedback requires macOS 11+ and a controller with rumble motors. Confirmed working:

| Controller       | Handles | Triggers |
|------------------|---------|----------|
| Xbox Wireless    | ✓       | ✓        |
| DualSense (PS5)  | ✓       | ✓ (adaptive) |
| DualShock 4 (PS4) | ✓      | —        |
| Nintendo Switch Pro | —    | —        |

See [`rumble`](../configuration/actions.md#rumble) action type for configuration.
