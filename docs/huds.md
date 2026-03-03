# HUDs

PadIO provides several floating overlays (HUDs) for feedback and navigation.

## Help HUD

Press the **menu (≡)** button at any time to open a floating overlay showing all effective button mappings for the current profile and mode.

- Navigate the list with **dpad up/down**
- Close with **B**, **X**, or **LT** (or press **menu** again)

The Help HUD takes priority over all other button processing while visible.

## Mode notification

When a mode switch occurs via `prev_mode`, `next_mode`, or `mode:<name>`, a small overlay briefly appears at the top of the screen displaying the new mode name. It auto-dismisses after 1.5 seconds.

## Debug overlay

When `"debug_overlay": true` is set in the config, a small pill-shaped HUD appears at the bottom of the screen on every button press, showing:

- **Top line**: button name (e.g. `A`, `dpad_up`)
- **Bottom line**: resolved action (e.g. `ctrl+a → n`, `media: play_pause`, `no mapping`)

The overlay auto-dismisses after 2 seconds. A new press resets the timer immediately.

Set `"debug_overlay": false` (or omit the field) for production use.
