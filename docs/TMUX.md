# tmux

The prefix is **`Ctrl-a`**, not the default `Ctrl-b`. Everything below is
written as `prefix` + key.

## Getting around

| Keys | Does |
|---|---|
| `prefix f` | **Jump to a project** — fzf over your project roots, then attach or create a session named after it |
| `prefix c` | new window, in the current directory |
| `prefix ,` | rename window |
| `prefix 1`…`9` | go to window N (windows start at 1, not 0) |
| `prefix <` / `prefix >` | move this window left / right; repeatable |
| `prefix d` | detach |
| `prefix s` | session list |

## Panes

| Keys | Does |
|---|---|
| `prefix \|` | split vertically, in the current directory |
| `prefix -` | split horizontally, in the current directory |
| `prefix h/j/k/l` | move between panes |
| `prefix H/J/K/L` | resize; repeatable, so hold the key |
| `prefix z` | zoom this pane full-screen (again to undo) |
| `prefix x` | kill this pane |
| `Ctrl-h/j/k/l` | move between panes **and nvim splits** interchangeably (vim-tmux-navigator) |

## Copy mode

| Keys | Does |
|---|---|
| `prefix [` | enter copy mode |
| `v` | start selecting |
| `y`, `Enter`, `Ctrl-c` | copy and exit — **also reaches the clipboard of your local machine** |
| `q` | leave copy mode without copying |
| `/` `?` | search forward / back |
| drag with the mouse | select — **does not copy**; press `y` |
| double / triple click | select the word / the line — again, no copy |
| scroll up | enter copy mode; scroll back to the bottom to leave it again |

Where the machine has its own clipboard tool — a Mac, a Linux desktop — the copy
is piped straight into it and works in any terminal. Where it does not, which is
every server you `ssh` to, it goes out over OSC 52 instead: no X11 forwarding
and no root, but it needs one setting in your terminal. Both cases, and how to
tell which one you are in, are in [docs/CLIPBOARD.md](CLIPBOARD.md).

### Selecting with the mouse the *terminal's* way

`mouse on` means tmux gets the drag, so your terminal's own selection — the one
`Cmd-C` copies — never happens. That is the price of clicking between panes and
dragging borders to resize, and it catches people out on macOS in particular,
because the old habit fails silently rather than visibly.

**Hold a modifier while you drag** to hand the mouse back to the terminal for
that one gesture: `Option` in iTerm2, `Fn` in Terminal.app, `Shift` in most
Linux terminals. Then copy the way you always did. Useful when you want a
selection that spans panes, or the pane's full width rather than what tmux
thinks the wrapped lines are.

### Where the mouse deliberately differs from stock tmux

Two of tmux's own mouse bindings are overridden, both for the same reason: the
default writes to the clipboard at a moment you did not ask it to.

**Letting go of a drag selects; it does not copy.** tmux copies and cancels on
release. A trackpad click carries a pixel or two of movement, which counts as a
drag, so merely focusing a pane overwrote whatever you had on the clipboard —
and a drag that caught one line too few cost you the whole gesture instead of a
nudge. Here the selection stays up and stays adjustable, exactly as after `v`.
`y`, `Enter` and `Ctrl-c` are what reach the clipboard, and `q` leaves without
touching it. Double and triple click are the same story by a second route: stock
tmux 3.x copies on both.

`Ctrl-c` is tmux's own "leave copy mode", which `q` already does; copying on the
way out is the more useful meaning, and it still leaves when nothing is
selected. It does **not** change `Ctrl-c` in a shell — the copy-mode key table
only exists while you are in copy mode, and an interrupt never goes through a
key table at all. `Cmd-C` and `Ctrl-Shift-C` cannot be bound: the terminal takes
those before tmux sees them. For those, use the modifier-drag below.

**The wheel is left alone**, which is worth saying because it is the one place
the reasoning points the other way. Scrolling up enters copy mode and scrolling
back to the bottom leaves it again (`copy-mode -e`), so glancing at what scrolled
past costs nothing and you keep typing. The price is that scrolling all the way
down *while a selection is up* takes the selection with it — but that is rarer
than the casual glance, and the alternative makes every scroll end in `q`, with
a pane stuck in copy mode looking like a hung program.

A pane running something that wants the mouse itself — nvim, `less` — still gets
every event untouched. That test is tmux's own and is kept in each binding.

## Keys tmux takes away from the shell

`Ctrl-h/j/k/l` are bound at the *root* table by vim-tmux-navigator, so they work
without the prefix and in any pane. The cost is that the shell never sees them:

| You wanted | You get | Instead press |
|---|---|---|
| `Ctrl-l` clear the screen | move to the pane on the right | **`prefix Ctrl-l`** |
| `Ctrl-h` backspace (some terminals) | move to the pane on the left | `Backspace` |

`prefix Ctrl-l` is the plugin's own compensation binding. There is none for
`Ctrl-h`; terminals that send `^H` for backspace are rare enough that it has not
been worth a second special case.

## macOS: check `default-command`

tmux-sensible sets `default-command` to `reattach-to-user-namespace -l $SHELL`
on macOS when that tool is installed (`sensible.tmux:101`). It is a leftover
from the days when pasteboard access needed it, and it is usually harmless — but
`default-command` **wins over `default-shell`**, which is what envup probes for
and sets, so on a Mac where `chsh` never ran you would silently get bash in
every pane rather than the zsh envup installed.

```bash
tmux show -gv default-command      # empty is what you want
```

If it is not empty and you do not want it, put this in
`modules/tmux/files/hosts/<hostname>.conf`, which is sourced after everything
else:

```tmux
set -g default-command ""
```

## Colours and `TERM`

Inside a pane, `TERM` is `tmux-256color` — the entry tmux itself ships, and the
only one that admits tmux can do italics. Where that entry is missing it is
`screen-256color` instead, which every ncurses since the nineties has.

Which one you get is decided at server start by asking `infocmp`, because naming
a terminfo entry the machine does not have is not a cosmetic problem: colours go
wrong and so do Home, End and the arrow keys. ncurses only added
`tmux-256color` in 6.0, so CentOS 7 and its relatives fall back, as do the slim
container images that ship no `infocmp` at all.

```bash
tmux show -s default-terminal    # which one this machine picked
```

One case the probe cannot see: a machine you `ssh` *to* from inside tmux
inherits this `TERM` and may not know the entry either. If you have one of
those, pin the old value for the machine you start tmux on:

```bash
# modules/tmux/files/hosts/<hostname>.conf
set -g default-terminal "screen-256color"
```

## The shell in a pane

Panes run **zsh, as a login shell**, wherever zsh is installed — even on a
machine where `chsh` could not change your login shell, which on a managed
server is most of them.

Login shell matters more than it sounds like it does. A pane that is not one
skips `/etc/profile`, `/etc/zprofile` and `~/.zprofile`, and you never notice
for as long as you start tmux by hand from a shell that already ran them and the
panes inherit the result. It shows up the first time something *else* starts the
server — continuum restoring after a reboot, a systemd user unit, `ssh box tmux
…` — and then `module`, conda and (on macOS) `path_helper` are missing from a
session you did not start differently on purpose. envup's own zsh config is
fine either way: `.zshenv` is read by every zsh.

```bash
tmux show -g default-shell      # which shell this machine picked
```

Scrollback is 50000 lines per pane, matching tmux-sensible — one compile or
benchmark run goes past the old 10000 without trying.

## Sessions that survive a reboot

The machine goes down — a kernel update, a power event, someone else's OOM. You
log back in, type one command, and your windows, panes, working directories,
scrollback and open files are where you left them.

Three pieces, and all three have to be there:

| Piece | Does |
|---|---|
| tmux-resurrect | writes the session tree to a file |
| tmux-continuum | saves every 5 minutes; restores when a tmux server starts |
| `tmux-resume` (`tm`) | starts that server, waits for the restore, attaches |

| Keys | Does |
|---|---|
| `prefix Ctrl-s` | save now |
| `prefix Ctrl-r` | restore now |

**Five minutes is the worst case.** That is the interval, so it is also the most
layout an unplanned reboot can cost you. Nothing is saved on shutdown, because a
machine going down does not stop to ask.

**Saves are per machine:** `~/.local/share/tmux/resurrect/<hostname>/`, under
`$XDG_DATA_HOME` if you set one. On a home directory shared over NFS the default
single directory means every machine writes the same file and the last save wins
— you log into the build box and it hands you the layout you left on the GPU
box. Not `/tmp` either way, so a reboot does not take them, and envup's `clean`
never touches them.

The name is the **short** hostname, the same one `~/.tmux/host.conf` is keyed by,
so a machine is called one thing everywhere in envup. Ask rather than assume:

```bash
tmux show -gv @resurrect-dir
```

### If you have saves from an earlier envup

The directory moved — twice, and the second time was a bug fix rather than a
rename. Nothing migrates your saves for you.

A **running** tmux server keeps whatever config it read at start, so it is still
writing to the old place until you reload:

```bash
tmux source ~/.tmux.conf
new="$(tmux show -gv @resurrect-dir)"; old=~/.local/share/tmux/resurrect
mkdir -p "$new"
cp -n "$old"/tmux_resurrect_*.txt "$old"/pane_contents.tar.gz "$new"/ 2>/dev/null
ln -sfn "$(cd "$new" && printf '%s\n' tmux_resurrect_*.txt | sort | tail -1)" "$new/last"
```

The newest save is picked by sorting the names rather than by asking `ls`: the
timestamp is in the filename, so the two orders agree — and envup itself aliases
`ls` to `eza`, which reads `-t` as "which time field", not "sort by time".

Without that, the next server start restores from an empty directory and looks
like it lost everything, when the files are one directory over.

**A directory literally named `\` in your home directory** is the bug that fix
was for: `@resurrect-dir` used to hold `$HOME/.../$HOSTNAME` as a string for
tmux-resurrect to expand later, and on at least one machine the value came back
out of the server with a backslash in front of each `$` — so the expansion
rewrote the `$HOME` inside it, left the backslash standing, and built a whole
tree under it. Everything in there is a save that went to the wrong place. Copy
the newest one out if you want it, then delete the tree; once
`tmux show -gv @resurrect-dir` prints a path with no backslash in it, nothing
writes there again.

Which layer put the backslash there is not yet known — tmux 2.7 and 3.7c both
hand the old line back unescaped. If you still have that server running on its
old config, it is holding the evidence in memory, and it is gone the moment you
reload:

```bash
tmux -V; tmux show-option -gqv @resurrect-dir | cat -A
```

The fix does not depend on the answer: it removes the round trip rather than the
escape, so there is nothing left for either parser to get wrong.

### Coming back: type `tm`, not `tmux`

```bash
tm            # or the full name, tmux-resume
```

**Plain `tmux` is the wrong command after a reboot**, and it fails in a way that
looks like the restore is broken rather than like you typed the wrong thing.
Starting the server is what triggers continuum's restore, but that restore is
asynchronous — it sleeps a second so tmux can finish sourcing its plugins —
while your `tmux` created a session *immediately*. You land in an empty session
named `0`, and your real layout appears beside it a moment later, one window
switch away, with nothing on screen to say so.

`tmux attach` is no better when the server is not running yet: there is nothing
to attach to, so it fails and never triggers the restore at all.

`tmux-resume` does the sequence that works:

| Situation | What it does |
|---|---|
| a server is already up | attaches to it |
| nothing saved | starts a session — there is nothing to wait for |
| a save on disk | starts the server, waits for the sessions to appear, attaches |

```bash
# ~/.zshrc.d/hosts/<machine>.zsh — this machine, permanently
ENVUP_TMUX_SESSION=work      # name for the session created when nothing restores
ENVUP_TMUX_RESTORE_WAIT=8    # seconds to wait for a restore before giving up
```

**Nothing runs it for you at login.** An earlier version attached automatically
from `.zshrc`, and it was removed: an automatic path has to guess whether *this*
connection wants a multiplexer, and every wrong guess puts you in a session that
is not the one you left — which is the exact failure the feature exists to
prevent. If you want it back for one machine, that is one line in
`~/.zshrc.d/hosts/<machine>.zsh` or `~/.zshrc.local`, where the guards are yours
to write:

```bash
[[ -o interactive && -z "$TMUX" && -t 0 ]] && tmux-resume
```

### nvim panes

A restored editor pane comes back with your buffers, splits and folds, not an
empty nvim. nvim writes a `Session.vim` in the pane's directory once a minute
while you work — on a timer rather than on exit, because a kernel that is going
down does not run `VimLeavePre`, and an exit hook would save exactly the sessions
you did not need.

A clean quit deletes the file again, so it only lingers when nvim was killed —
which is the case it exists for. envup's global gitignore covers `Session.vim`
for the times a crash leaves one in a repository. It is only ever written inside
tmux; turn it off entirely with `vim.g.envup_session = false` in
`hosts/<machine>.lua`.

## `prefix f` — the sessionizer

The problem it solves: switching projects used to mean remembering which
numbered session you had put one in, or opening a second session for a project
you already had open. Here the session name *is* the project name, so picking a
project you are already in re-attaches to it.

```
prefix f          pick a project with fzf
ts                the same picker, from the shell (also works outside tmux)
ts ~/work/thing   skip the picker
```

`ts` is only defined if nothing else on the machine is called `ts` — moreutils
ships one. The script is always available under its full name,
`tmux-sessionizer`.

From tmux 3.2 the picker opens in a **popup** over the current pane: your layout
does not move, and there is no window left behind if you change your mind. Older
tmux gets a throwaway window instead, which is what everyone got before. Nothing
to configure — the binding asks the running server which it is, so upgrading
tmux is enough on its own.

```bash
tmux set-environment -g ENVUP_TS_POPUP 0    # window even on a new tmux
tmux set-environment -g ENVUP_TS_POPUP 1    # popup even on an old one
```

The same line in `hosts/<hostname>.conf` makes it permanent for that machine.

Killing a session (`prefix &` on its last window, or `tmux kill-session`) moves
you to another one rather than detaching you. Once several projects are open at
once, closing one of them should no more drop you back to the login shell than
closing a browser tab should quit the browser. With nothing left to switch to it
detaches, as before.

### Telling it where your projects are

Out of the box it globs `~/work/*`, `~/src/*`, `~/projects/*`, `~/dev/*`,
`~/repos/*` and `~/go/src/*/*`. If your code lives somewhere else, list the
globs one per line:

```bash
mkdir -p ~/.config/envup
cat > ~/.config/envup/project-dirs <<'EOF'
~/code/*
/data/experiments/*
EOF
```

A file rather than an exported variable, because a tmux key binding runs under
the tmux *server's* environment — which never sourced your `.zshrc`. The file is
read the same way from both. (`$ENVUP_PROJECT_DIRS`, colon-separated, still wins
if it is set; it is there for scripting.)

## Per-machine config

Two layers, both loaded after the plugins so either can override them.

**`modules/tmux/files/hosts/<hostname>.conf` — committed.** This is where
machine-specific settings belong: the status bar colour that tells you which box
you are on, a toolchain binding, a longer escape-time for a slow link. Because
it is in the repo it syncs to your other machines and survives a rebuild, and
because it is keyed by hostname it stays separate from the others even on a home
directory shared over NFS.

```bash
cp modules/tmux/files/hosts/example.conf.template \
   modules/tmux/files/hosts/$(hostname -s).conf
$EDITOR modules/tmux/files/hosts/$(hostname -s).conf
envup install tmux          # links it to ~/.tmux/host.conf
tmux source ~/.tmux.conf
```

tmux cannot expand `$(hostname)` inside `source-file`, which is why envup
resolves the name at install time and links your file to one fixed path. Adding
a new host file therefore needs one `envup install tmux` to pick it up.

**`~/.tmux.local` — not in the repo.** Private or throwaway settings. Loaded
last, so it wins over everything.

## Plugins

TPM plus sensible, resurrect, continuum and vim-tmux-navigator, all vendored as
git submodules — so a fresh machine does not need to reach GitHub to get a
working tmux.

| Keys | Does |
|---|---|
| `prefix I` | install / update plugins |
| `prefix r` | reload `~/.tmux.conf` |

## Related

- [docs/CLIPBOARD.md](CLIPBOARD.md) — making copy actually reach your laptop
- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — how the config layers fit together
