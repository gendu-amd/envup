# tmux

The prefix is **`Ctrl-a`**, not the default `Ctrl-b`. Everything below is
written as `prefix` + key.

## Getting around

| Keys | Does |
|---|---|
| `prefix f` | **Jump to a project** — fzf over your project roots, then attach or create a session named after it |
| `prefix c` | new window |
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
| `y` | copy and exit — **also reaches the clipboard of your local machine** |
| `q` | leave copy mode |
| `/` `?` | search forward / back |

The copy goes out over OSC 52, so it works on any server without X11
forwarding or root. It needs one setting in your terminal — see
[docs/CLIPBOARD.md](CLIPBOARD.md).

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

## Sessions that survive a reboot

The machine goes down — a kernel update, a power event, someone else's OOM. You
log back in and your windows, panes, working directories, scrollback and open
files are where you left them. You do not type anything to make that happen.

Three pieces, and all three have to be there:

| Piece | Does |
|---|---|
| tmux-resurrect | writes the session tree to a file |
| tmux-continuum | saves every 5 minutes; restores when a tmux server starts |
| `~/.zshrc.d/90-tmux.zsh` | starts that server when you log in |

| Keys | Does |
|---|---|
| `prefix Ctrl-s` | save now |
| `prefix Ctrl-r` | restore now |

**Five minutes is the worst case.** That is the interval, so it is also the most
layout an unplanned reboot can cost you. Nothing is saved on shutdown, because a
machine going down does not stop to ask.

**Saves are per machine:** `~/.local/share/tmux/resurrect/<hostname>/`. On a home
directory shared over NFS the default single directory means every machine writes
the same file and the last save wins — you log into the build box and it hands
you the layout you left on the GPU box. Not `/tmp` either way, so a reboot does
not take them, and envup's `clean` never touches them.

### Logging in

The login hook is the piece that was missing: without it your layout sat in a
file waiting for you to remember to type `tmux`. On an interactive login it
starts a server if none is running, waits for continuum's restore (which is
asynchronous — creating a session too early would leave you in an empty shell
with the real work restored behind it), and attaches.

It stays out of the way when it should: not for `scp`/`rsync`/`ssh box cmd`, not
inside an existing tmux or screen, not in VS Code's or Cursor's integrated
terminal, and not when tmux is missing. It does not `exec`, so detaching leaves
you in a normal shell and a broken tmux cannot lock you out of the machine.

```bash
NO_TMUX=1 ssh box            # just this connection
```

```bash
# ~/.zshrc.d/hosts/<machine>.zsh — this machine, permanently
ENVUP_TMUX_AUTOATTACH=0      # never
ENVUP_TMUX_AUTOATTACH=1      # yes, even in an editor terminal
ENVUP_TMUX_SESSION=work      # name for the session created when nothing restores
ENVUP_TMUX_RESTORE_WAIT=8    # seconds to wait for a restore before giving up
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
