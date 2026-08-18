# Custom Menus

Named menus are defined at the top level of the config under `"menus"`. Each menu is a list of `{ label, action }` pairs and is opened via the `menu:<name>` action type.

## Defining a menu

```json
"menus": {
  "git": [
    { "label": "git status",  "action": { "type": "keystroke", "key": "`git status\n`" } },
    { "label": "git diff",    "action": { "type": "keystroke", "key": "`git diff\n`" } },
    { "label": "git push",    "action": { "type": "keystroke", "key": "`git push\n`" } }
  ]
}
```

## Opening a menu

Open it from any binding:

```json
"Y": { "type": "menu", "name": "git" }
```

The legacy syntax `"type": "menu:git"` is also supported.

## Menu styles

A menu is drawn either as a vertical **list** (the default) or as a circular **wheel**.

Set the default for every menu at the top level of the config:

```json
"menu_style": "wheel"
```

Accepted values are `"list"` and `"wheel"` (`"donut"` and `"radial"` are accepted as aliases for `"wheel"`). An unrecognised value falls back to `"list"` and logs a warning rather than rejecting the config.

To override the style for one menu, write that menu as an object with `style` and `items` instead of a bare array:

```json
"menus": {
  "git": [
    { "label": "git status", "action": { "type": "keystroke", "key": "`git status\n`" } }
  ],

  "window": {
    "style": "wheel",
    "items": [
      { "label": "Left half",  "action": { "type": "keystroke", "key": "left",  "modifiers": ["ctrl", "opt"] } },
      { "label": "Right half", "action": { "type": "keystroke", "key": "right", "modifiers": ["ctrl", "opt"] } },
      { "label": "Maximize",   "action": { "type": "keystroke", "key": "up",    "modifiers": ["ctrl", "opt"] } },
      { "label": "Centre",     "action": { "type": "keystroke", "key": "c",     "modifiers": ["ctrl", "opt"] } }
    ]
  }
}
```

Both forms can be mixed freely in one config. A menu written as a bare array inherits the top-level `menu_style`.

!!! note
    The wheel is meant for short menus. A menu with more than 16 items is drawn as a list regardless of its style, and logs a warning.

## Navigation

### List style

- **dpad up/down** (or **left/right**) — move highlight
- **A** or **RT** — select item and execute its action
- **B**, **X**, or **LT** — cancel and close

### Wheel style

Items sit on a ring around a hub that spells out the current selection. There are two ways to drive it, both live at the same time:

- **either thumbstick** — aim. The ring stays still and the highlight jumps to whichever item the stick points at. Letting the stick return to centre keeps the current selection.
- **dpad left/right** (or **up/down**) — rotate. The ring turns and the highlight stays on the fixed marker at the 12 o'clock position.
- **A** or **RT** — select item and execute its action
- **B**, **X**, or **LT** — cancel and close

Selection and cancellation use the same buttons in both styles.

## Sizing

Menus scale with the top-level `hud_zoom` setting along with every other HUD. See [HUDs](../huds.md).

## Nested menus

Menu item actions can be any action type, including another `menu:<name>` for nested menus.
