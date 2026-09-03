# Clipboard over SSH (OSC 52)

Copy something on a server — a log line, a stack trace, a command you spent
twenty minutes getting right — and have it land on the clipboard of the machine
you are actually sitting at. No X11 forwarding, no root, no daemon, no second
network path: the text rides back over the SSH connection that is already open,
as a terminal escape sequence.

That constraint set is why envup uses OSC 52 **on a server**. It is the only
clipboard route that works on a machine you do not administer.

It is also the wrong route when you are sitting at the machine tmux is running
on — a Mac with tmux started locally, a Linux desktop — because OSC 52 needs the
terminal to cooperate and `pbcopy` does not. So both tmux and nvim check for a
real clipboard tool first and only fall back to escape sequences. **Which one
you are on decides everything below**: the terminal support table matters for
the remote case and not for the local one.

## What envup configures for you

| Layer | What it does | Where |
|---|---|---|
| tmux | pipes copies into this machine's own clipboard tool — `pbcopy`, `clip.exe`, `wl-copy`, `xclip`/`xsel` — when it has one | `modules/tmux/files/.tmux.conf` |
| tmux | `set -s set-clipboard on` — accept OSC 52 from applications *and* send tmux's own copies onward, for when it does not | same |
| tmux | `Ms` terminal capability, which tmux requires before it will emit anything | same |
| nvim | an OSC 52 clipboard provider, copy-only, installed only when the machine has no real clipboard tool | `modules/nvim/files/lua/configs/clipboard.lua` |

The two probes are deliberately the same, in the same order, and neither takes
presence on `PATH` as the answer — `xclip` with no `DISPLAY` is an error
message, not a clipboard. If you change one, change the other.

```bash
tmux show -gv @envup-copy-cmd    # what tmux picked here; empty means OSC 52
```

Then, in practice:

- **tmux**: enter copy mode (`prefix + [`), select with `v`, copy with `y`.
  Mouse selection works too.
- **nvim**: just yank. NvChad sets `clipboard=unnamedplus`, so `y`, `dd` and
  friends all go to the system clipboard.

## What you have to do yourself: the terminal

This section is about the **remote** case. If tmux is running on the machine you
are sitting at, envup is already using its native clipboard and none of the
below applies.

envup cannot configure the program running on your laptop. Copy will silently
do nothing until the terminal on *that* end supports OSC 52 and has it enabled.

| Terminal | Copy (write) | Note |
|---|---|---|
| **Windows Terminal** | ✅ | On by default. Settings → your profile → *Terminal Emulation* has a switch to disable it (1.23+). |
| **VS Code / Cursor** | ✅ | **Off by default.** Set `"terminal.integrated.enableClipboardWrite": true` in `settings.json`. Older builds spell it `terminal.integrated.allowOsc52` — search the settings UI for "OSC 52". |
| PowerShell in the legacy console window (conhost) | ❌ | Not supported and not going to be. Run PowerShell *inside* Windows Terminal instead. |
| **iTerm2** | ✅ | **Off by default.** *Settings → General → Selection → Applications in terminal may access clipboard.* |
| **macOS Terminal.app** | ❌ | Never implemented it, and there is no setting. Use iTerm2, or one of the others below, for a remote clipboard. |
| kitty, Alacritty, WezTerm, mintty | ✅ | On by default. |
| GNOME Terminal | ❌ | VTE has never implemented it. |

**Nobody supports paste (read), on purpose.** Letting a remote program read your
clipboard is a real security hole, so terminals implement OSC 52 write-only.
This is not a limitation to work around — see below.

## Testing it in ten seconds

From the server, outermost layer first. Each step should put a different word on
your laptop's clipboard; paste somewhere after each one to see how far you get.

```bash
# 1. the terminal itself — run this OUTSIDE tmux
printf '\033]52;c;%s\a' "$(printf 'terminal-ok' | base64 | tr -d '\n')"

# 2. through tmux — run the exact same line INSIDE a tmux pane
printf '\033]52;c;%s\a' "$(printf 'tmux-ok' | base64 | tr -d '\n')"

# 3. tmux's own copy path — prefix + [ , select with v , copy with y

# 4. nvim — :put ='nvim-ok' then yank the line with yy
```

Where it stops tells you which layer to look at:

- **1 fails** → the terminal. Check the table above; if you are in VS Code /
  Cursor, this is almost certainly the missing `enableClipboardWrite`.
- **1 works, 2 fails** → tmux. `tmux show -s set-clipboard` must print `on`
  (the tmux default is `external`, which drops sequences coming *from*
  applications). If it does, check the capability:
  `tmux show -s terminal-overrides | grep Ms`.
- **2 works, 3 fails** → tmux's own copy path. Ask it what it picked first:
  `tmux show -gv @envup-copy-cmd`. A **name** means it is piping into that tool,
  so test the tool itself (`echo hi | pbcopy`) rather than the terminal.
  **Empty** means it is on OSC 52, and a tmux older than 2.6 lacks the `Ms`
  mechanism entirely — nothing to do but upgrade it.
- **3 works, 4 fails** → nvim. `:echo g:clipboard` should show `OSC 52`. If it
  shows something else, this machine has a native clipboard tool and nvim is
  using it (see below).

## Deliberate decisions worth knowing about

**Paste in nvim comes from nvim's own register, not the terminal.** nvim 0.10
ships an OSC 52 *reader*, and using it would be a trap: it asks the terminal for
the clipboard and waits for a reply that Windows Terminal and VS Code will never
send, so every `p` freezes for the full timeout — about ten seconds. So the
provider stubs paste to return the unnamed register instead. To paste something
from the outside world, use the terminal's own paste (`Ctrl+Shift+V`); it
arrives as ordinary keystrokes and nvim never knows the difference.

**nvim only takes over when there is nothing better.** On a machine with a
working `pbcopy`, `wl-copy`, or `xclip`-plus-a-real-`DISPLAY`, nvim keeps its
native provider, which can paste as well as copy. `clipboard.lua` checks for a
*usable* tool, not just one on `PATH` — `xclip` with no display is an error
message, not a clipboard. To override the decision on one machine, set
`vim.g.clipboard` in `hosts/<hostname>.lua`. tmux applies the same rule; the
two used to disagree, and tmux was the one that was wrong.

**A native tool copies to the machine it runs on, which is not always yours.**
If you `ssh` *into* a Mac and use tmux there, `pbcopy` puts the text on that
Mac's clipboard, not on the one in front of you. This is the same trade nvim has
always made, and it is the right default — the local case is the common one, and
the tool is the only route that works in every terminal. For a machine where you
want the escape sequence instead, unset the choice in
`modules/tmux/files/hosts/<hostname>.conf`, which is sourced after everything
else:

```tmux
bind -T copy-mode-vi y send -X copy-selection-and-cancel
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-selection-no-clear
```

**Large copies are refused, loudly.** Terminals cap the size of a single escape
sequence and drop an oversized one without a word, which looks exactly like
"the clipboard didn't update". Past 64 KB nvim tells you instead of pretending.

**The wildcard `Ms` override is safe.** envup adds
`Ms` for `*`, not just `xterm*`, because `screen*` and whatever a locked-down
box reports need it too. A terminal that does not understand OSC 52 ignores the
sequence.

## Related

- [docs/TMUX.md](TMUX.md) — the rest of the tmux setup
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — how the config layers fit together
