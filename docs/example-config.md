# Example Config

A complete annotated config demonstrating profiles, modes, sequences, custom menus, and axis mappings.

```json
{
  "trigger_threshold": 0.5,
  "debug_overlay": false,
  "global": {
    "left_stick":  { "type": "mouse_move", "speed": 15, "modifier": "RB", "modifier_speed": 3 },
    "right_stick": { "type": "scroll", "speed": 3, "y_inverted": true },
    "L3":          { "type": "left_click" },
    "R3":          { "type": "right_click" }
  },
  "profiles": {
    "default": {
      "apps": [],
      "default_mode": "general",
      "global": {
        "options": { "type": "mode_select" }
      },
      "modes": {
        "general": {
          "A":          { "type": "keystroke", "key": "space" },
          "B":          { "type": "keystroke", "key": "escape" },
          "dpad_up":    { "type": "keystroke", "key": "up" },
          "dpad_down":  { "type": "keystroke", "key": "down" },
          "dpad_left":  { "type": "keystroke", "key": "left" },
          "dpad_right": { "type": "keystroke", "key": "right" },
          "LB":         { "type": "keystroke", "key": "play_pause" },
          "RB":         { "type": "keystroke", "key": "next_track" }
        }
      }
    },
    "terminal": {
      "apps": ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2"],
      "default_mode": "shell",
      "global": {
        "options": { "type": "mode_select" },
        "LB":      { "type": "prev_mode" },
        "RB":      { "type": "next_mode" }
      },
      "modes": {
        "shell": {
          "A":          { "type": "keystroke", "key": "return" },
          "B":          { "type": "keystroke", "key": "c", "modifiers": ["ctrl"] },
          "X":          { "type": "keystroke", "key": "l", "modifiers": ["ctrl"] },
          "Y":          { "type": "menu:git" },
          "dpad_up":    { "type": "keystroke", "key": "up" },
          "dpad_down":  { "type": "keystroke", "key": "down" },
          "dpad_left":  { "type": "keystroke", "key": "left" },
          "dpad_right": { "type": "keystroke", "key": "right" }
        },
        "nvim": {
          "A":            { "type": "keystroke", "key": "return" },
          "B":            { "type": "keystroke", "key": "escape" },
          "X":            { "type": "keystroke", "key": "u" },
          "Y":            { "type": "keystroke", "key": "r", "modifiers": ["ctrl"] },
          "dpad_up":      { "type": "keystroke", "key": "k" },
          "dpad_down":    { "type": "keystroke", "key": "j" },
          "dpad_left":    { "type": "keystroke", "key": "h" },
          "dpad_right":   { "type": "keystroke", "key": "l" },
          "X+dpad_up":    { "type": "keystroke", "key": "k", "modifiers": ["ctrl"] },
          "X+dpad_down":  { "type": "keystroke", "key": "j", "modifiers": ["ctrl"] }
        },
        "tmux": {
          "A": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "return" }
            ],
            "delay": 0.05
          },
          "dpad_up": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "up" }
            ]
          },
          "dpad_down": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "down" }
            ]
          },
          "dpad_left": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "left" }
            ]
          },
          "dpad_right": {
            "type": "sequence",
            "steps": [
              { "type": "keystroke", "key": "a", "modifiers": ["ctrl"] },
              { "type": "keystroke", "key": "right" }
            ]
          }
        }
      }
    }
  },
  "menus": {
    "git": [
      { "label": "git status",    "action": { "type": "keystroke", "key": "`git status\n`" } },
      { "label": "git diff",      "action": { "type": "keystroke", "key": "`git diff\n`" } },
      { "label": "git log",       "action": { "type": "keystroke", "key": "`git log --oneline -20\n`" } },
      { "label": "git pull",      "action": { "type": "keystroke", "key": "`git pull\n`" } },
      { "label": "git push",      "action": { "type": "keystroke", "key": "`git push\n`" } },
      { "label": "git stash",     "action": { "type": "keystroke", "key": "`git stash\n`" } },
      { "label": "git stash pop", "action": { "type": "keystroke", "key": "`git stash pop\n`" } }
    ]
  }
}
```

This config:

- Maps the **left stick** to mouse movement globally, with RB as a speed boost modifier
- Maps the **right stick** to scrolling globally (inverted Y for natural scroll)
- **L3/R3** (stick clicks) for left/right click
- **Default profile**: basic arrow keys, space, escape, media controls
- **Terminal profile**: activated for Ghostty, Terminal, and iTerm2
    - **shell mode**: return, ctrl-c, ctrl-l, git menu on Y
    - **nvim mode**: vim-style hjkl navigation, with X+dpad combos for ctrl-j/ctrl-k (half-page scroll)
    - **tmux mode**: prefix sequences (ctrl-a + key) for pane navigation
- **Git menu**: quick terminal commands accessible via Y button in shell mode
