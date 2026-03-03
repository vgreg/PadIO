# Custom Menus

Named menus are defined at the top level of the config under `"menus"`. Each menu is an array of `{ label, action }` pairs and is opened via the `menu:<name>` action type.

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
"Y": { "type": "menu:git" }
```

## Navigation

- **dpad up/down** — move highlight
- **A** or **RT** — select item and execute its action
- **B**, **X**, or **LT** — cancel and close

## Nested menus

Menu item actions can be any action type, including another `menu:<name>` for nested menus.
