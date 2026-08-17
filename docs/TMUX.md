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

## Sessions that survive

resurrect + continuum are configured, so the layout you were working in is saved
every 15 minutes and restored when the tmux server next starts — including each
pane's visible scrollback and your nvim sessions.

| Keys | Does |
|---|---|
| `prefix Ctrl-s` | save now |
| `prefix Ctrl-r` | restore now |

Saves live in `~/.local/share/tmux/resurrect/` — or `~/.tmux/resurrect/` if you
still have one from an older setup, which resurrect keeps using. Either way not
`/tmp`, so a reboot does not take them, and envup's `clean` never touches them.

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
