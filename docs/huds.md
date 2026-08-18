# HUDs

PadIO provides several floating overlays (HUDs) for feedback and navigation.

## Help HUD

Press the **menu (≡)** button at any time to open a floating overlay showing all effective button mappings for the current profile and mode.

- Navigate the list with **dpad up/down**
- Close with **B**, **X**, or **LT** (or press **menu** again)

The Help HUD takes priority over all other button processing while visible.

## Custom menu

Opened with a `menu:<name>` action, this overlay lists the items of a [custom menu](configuration/menus.md) and executes the one you pick. It comes in two styles, chosen with `menu_style` (globally) or a per-menu `style` key:

- **List** (default) — a vertical list, navigated with the dpad.
- **Wheel** — a circular "donut" with the items on a ring around a hub showing the current selection. Aim it with either thumbstick, or rotate the ring with dpad left/right against a fixed marker at 12 o'clock.

Like the Help HUD, the custom menu consumes all button input while it is visible. Pointer and scroll emission from the sticks is suspended too, so a stick can aim the wheel without moving the mouse underneath.

## Mode notification

When a mode switch occurs via `prev_mode`, `next_mode`, or `mode:<name>`, a small overlay briefly appears at the top of the screen displaying the new mode name. It auto-dismisses after 1.5 seconds.

## Debug overlay

When `"debug_overlay": true` is set in the config, a small pill-shaped HUD appears at the bottom of the screen on every button press, showing:

- **Top line**: button name (e.g. `A`, `dpad_up`)
- **Bottom line**: resolved action (e.g. `ctrl+a → n`, `media: play_pause`, `no mapping`)

The overlay auto-dismisses after 2 seconds. A new press resets the timer immediately.

Set `"debug_overlay": false` (or omit the field) for production use.

## Sizing

The top-level `hud_zoom` key scales every HUD on this page at once:

```json
"hud_zoom": 1.5
```

The default is `1.0`; values are clamped to the range 0.75–3.0. This is worth turning up when the controller is being used from across the room rather than at the desk.
