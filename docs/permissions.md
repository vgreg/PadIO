# Permissions

PadIO requires **Accessibility** permission to post synthetic keyboard events to other applications.

## Granting access

- Open the **PadIO menu bar icon** → **Grant Accessibility Access** to trigger the system prompt.
- Or go to **System Settings → Privacy & Security → Accessibility** and add PadIO manually.

## Actions that skip Accessibility

The following action types do **not** require Accessibility permission and work unconditionally:

- Media key events (`play_pause`, `next_track`, `volume_up`, etc.)
- `keyboard_viewer`
- `next_input_source`
- `rumble` (haptic feedback — routes directly to the controller hardware)
