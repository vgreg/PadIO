# Automatic Modes

PadIO can switch mode by itself based on what you are actually doing, instead of you picking a mode by hand every time. An external program reports a short **context token** (usually the name of the app you are working in), and each profile maps tokens to modes.

The motivating case is a terminal multiplexer: focus a Claude Code pane and the controller is in agent mode, move to a shell pane and it is in shell mode, launch `nvim` and it becomes vim mode. But nothing about the mechanism is terminal-specific. Any program that can write a file can drive it.

## How it works

PadIO watches `~/.config/padio/context`, a plain text file holding one token:

```
claude
```

When the token **changes**, PadIO looks it up in the active profile's `context_modes` and switches mode if there is a match.

```
producer                        PadIO
────────                        ─────
write ~/.config/padio/context ──> file watch → context_modes → mode
```

## Configuration

Add `context_modes` to a profile. Keep bindings that should always be available in the profile's `global`, so they survive every mode change:

```json
"profiles": {
  "terminal": {
    "apps": ["com.mitchellh.ghostty"],
    "default_mode": "shell",
    "global": {
      "options": { "type": "mode_select" }
    },
    "context_modes": {
      "claude": "agent",
      "nvim": "nvim",
      "zsh": "shell",
      "ssh": "shell"
    },
    "hidden_modes": ["agent", "nvim"],
    "modes": {
      "shell": { },
      "agent": { },
      "nvim": { }
    }
  }
}
```

| Field           | Type   | Description |
|-----------------|--------|-------------|
| `context_modes` | object | Maps a context token to a mode name. Matching is exact. |

## Resolution rules

Four rules govern automatic switching. They exist to keep it from fighting you.

**1. It fires only when the token changes.** A producer rewriting the same token repeatedly does nothing.

**2. No match leaves the mode alone.** A token with no `context_modes` entry keeps the current mode. It does *not* fall back to `default_mode`. This is what makes it practical to add entries only for the apps you care about, and to ignore everything else.

**3. A mode you picked by hand sticks.** Because switching happens only on token *change*, a mode chosen from the picker survives until you move to a different app. Pick `media` by hand inside a Claude pane and it stays `media`; move to an `nvim` pane and it becomes `nvim`.

**4. An unknown mode name is ignored.** If `context_modes` names a mode that exists in neither the profile's `modes` nor `shared_modes`, PadIO logs it and does nothing.

Only the active profile is consulted, so a token means whatever that profile says it means, and nothing at all in a profile with no `context_modes`.

Returning to a profile re-applies the current token rather than snapping back to `default_mode`, so switching away from your terminal and back keeps the app-driven mode.

## Hidden modes

Automatic switching tends to produce one mode per app, which makes the mode picker unwieldy when only a couple of modes are ever chosen by hand. `hidden_modes` keeps them out of the way:

```json
"hidden_modes": ["agent", "nvim"]
```

Hidden modes are excluded from the [`mode_select`](actions.md#mode_select) picker and from [`prev_mode` / `next_mode`](actions.md#prev_mode-next_mode) cycling. They remain fully reachable via `context_modes`, [`mode:<name>`](actions.md#modename), and `default_mode`.

The key can go on a profile, or at the top level for modes shared across profiles. The two lists are combined.

```json
{
  "hidden_modes": ["media"],
  "profiles": {
    "terminal": {
      "hidden_modes": ["agent", "nvim"]
    }
  }
}
```

If hiding would leave nothing to show, PadIO shows every mode instead, so the picker can never become an empty panel you cannot escape.

!!! note
    Cycling with `prev_mode` / `next_mode` while a hidden mode is active moves you into the visible set, since the current mode is not part of the cycle.

## The context file

The file is a general-purpose extension point. PadIO does not care what writes it.

| Property | Behaviour |
|----------|-----------|
| Path     | `~/.config/padio/context` |
| Content  | A single token. Surrounding whitespace and newlines are stripped. |
| Empty or missing | Treated as no context. Not an error, and never a mode change. |
| Updates  | Picked up immediately, whether written in place or replaced atomically. |

Producers should write atomically, to a temp file in the same directory followed by a rename, so PadIO never reads a half-written token. PadIO ignores a rewrite of an unchanged token, so a producer that cannot easily detect changes may simply write every time.

A minimal producer is a one-liner:

```bash
printf 'nvim' > ~/.config/padio/context.tmp && mv ~/.config/padio/context.tmp ~/.config/padio/context
```

Which means anything can drive it: a shell hook on directory change, a window manager, a build script that switches you into a "watching CI" mode, or your editor.

## herdr integration

[herdr](https://herdr.dev/) is a terminal multiplexer for running coding agents, with workspaces, tabs and panes. The [herdr-padio](https://github.com/vgreg/herdr-padio) plugin is a ready-made producer for it:

```
herdr plugin install vgreg/herdr-padio
```

It watches the focused pane and writes the app running in it. Tokens are herdr's own agent name when it has detected one (`claude`), and otherwise the program driving the pane (`zsh`, `nvim`, `ssh`). Wrapped programs that report an unhelpful name can be renamed with substring rules; see that project's README.

With herdr, put the workspace, tab and pane navigation bindings in the profile's `global` so they work in every mode, and let `context_modes` handle the app in the pane.
