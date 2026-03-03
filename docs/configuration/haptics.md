# Haptics

PadIO can rumble connected controllers in response to system events. All haptic configuration is optional and opt-in — omit the `haptics` key entirely to disable all system-event rumble.

```json
"haptics": {
  "on_system_beep": {
    "intensity": 0.5,
    "sharpness": 0.3,
    "duration": 0.2
  },
  "on_notification": {
    "intensity": 0.6,
    "sharpness": 0.4,
    "duration": 0.25,
    "apps": ["com.apple.MobileSMS", "com.tinyspeck.slackmacgap"]
  }
}
```

## `on_system_beep`

Rumble whenever macOS plays a system alert sound (the error "beep"). Fires on all connected controllers.

| Field       | Type   | Default | Description |
|-------------|--------|---------|-------------|
| `intensity` | number | `0.5`   | Motor strength (0.0–1.0). |
| `sharpness` | number | `0.3`   | Haptic sharpness (0.0–1.0). |
| `duration`  | number | `0.2`   | Rumble duration in seconds. |

## `on_notification`

Rumble when a user notification is delivered by any app (or a filtered list of apps).

| Field       | Type            | Default | Description |
|-------------|-----------------|---------|-------------|
| `intensity` | number          | `0.6`   | Motor strength (0.0–1.0). |
| `sharpness` | number          | `0.4`   | Haptic sharpness (0.0–1.0). |
| `duration`  | number          | `0.25`  | Rumble duration in seconds. |
| `apps`      | array of strings | all apps | If set, only rumble when the notification comes from one of these bundle IDs. Omit or leave empty to rumble for all apps. |

## `rumble` action type

You can also trigger a rumble directly from any button binding using the [`rumble`](actions.md#rumble) action type, independently of the system-event triggers above.
