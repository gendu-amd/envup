# Changelog

All notable changes to envup are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Daily-use ergonomics on remote machines. 0.2.0 made envup install correctly on a
server you don't control; this makes the result pleasant to work in. No breaking
changes — every addition is inert until you create the file that uses it.

### Per-machine config, for every module that needs it

- **`hosts/<hostname>` layer extended to tmux, nvim and git.** zsh has had one
  since 0.2.0; it was the only module where machine-specific settings had a
  committed home. Now each has the same pair — repo default → committed
  per-machine → private file outside the checkout — with a template to copy:
  `modules/{tmux,nvim,git}/files/hosts/example.*.template`.
- zsh and nvim resolve the hostname themselves at startup. tmux's `source-file`
  and git's `[include]` expand nothing, so envup resolves `$ENVUP_HOST` at
  install time and links this machine's file to `~/.tmux/host.conf` /
  `~/.gitconfig.host`. Adding a *new* host file therefore needs one
  `envup install <module>`; editing an existing one does not.
- The links are declared optional (`?` prefix), so the machines without a host
  file — which is most of them — are unaffected.

### Clipboard over SSH

- **OSC 52 end to end.** Copy in tmux or yank in nvim on a server and the text
  lands on the clipboard of the machine you are sitting at, over the SSH
  connection already open. No X11 forwarding, no root, no daemon.
- tmux: `set-clipboard on` (the default `external` silently drops sequences
  coming *from* applications, so an nvim yank went nowhere) plus an `Ms`
  terminfo override for `*`, without which tmux emits nothing at all.
- nvim: an OSC 52 provider that installs itself **only** when the machine has no
  usable native clipboard tool — `xclip` with no `DISPLAY` doesn't count. Paste
  deliberately reads nvim's own register rather than querying the terminal:
  terminals implement OSC 52 write-only on purpose, so the built-in reader
  blocks for its full ~10s timeout on every `p`. Copies over 64 KB are refused
  with a message instead of being dropped by the terminal in silence.
- New [docs/CLIPBOARD.md](docs/CLIPBOARD.md): terminal support table, a
  layer-by-layer test, and what to enable locally. **VS Code / Cursor ship OSC 52
  write turned off** (`terminal.integrated.enableClipboardWrite`); the legacy
  conhost PowerShell window does not support it at all.

### Sessions that survive a reboot

- **`tmux-resume` (short name `tm`) puts you back in what the reboot
  interrupted.** resurrect and continuum were already configured; the missing
  half was the command you type afterwards. Plain `tmux` is the wrong one and
  fails in a way that reads as "the restore is broken": starting the server is
  what triggers continuum's restore, but that restore is asynchronous — it
  sleeps a second so tmux can finish sourcing its plugins — while your `tmux`
  created a session immediately, so you land in an empty `0` and your real
  layout arrives beside it with nothing on screen to say so. `tmux attach` is no
  better before the server is up: nothing to attach to, and the restore is never
  triggered. `tmux-resume` attaches to a running server, or starts one, waits
  for the sessions to appear, and attaches to those — and only waits when there
  is a save file, so a first run doesn't pay the timeout to learn there was
  nothing to restore.
- **Nothing attaches for you at login.** An interactive-login hook was written
  first (`90-tmux.zsh`) and removed before release. Deciding automatically
  whether *this* connection wants a multiplexer means sometimes deciding wrong,
  and a wrong guess drops you into a session that is not the one you left —
  which is the failure the whole feature exists to prevent, now arriving by a
  route you didn't ask for. `tests/unit/tmuxrestore.bats` asserts no zsh slice
  starts a tmux server, so it cannot come back by accident. Want it on one
  machine? One line in `~/.zshrc.d/hosts/<machine>.zsh`, with the guards you
  choose: `[[ -o interactive && -z "$TMUX" && -t 0 ]] && tmux-resume`.
- **One resurrect save directory per machine**
  (`~/.local/share/tmux/resurrect/$HOSTNAME`). The default is a single shared
  path, which on a home directory mounted over NFS means every machine writes
  the same file and the last save wins — you log into the build box and it
  restores the layout you left on the GPU box.
- **`@continuum-save-interval` 15 → 5**, so an unplanned reboot costs at most
  five minutes of window shuffling.
- **`@resurrect-strategy-nvim 'session'` finally does something.** The strategy
  restores a pane with `nvim -S` only when the pane's directory contains a
  `Session.vim`, and nothing in this config ever wrote one — the setting had been
  inert since the day it was added. New `lua/configs/session.lua` writes it on a
  timer (a kernel going down does not run `VimLeavePre`, so an exit hook would
  save every session except the ones this exists for), only inside tmux, and
  deletes it on a clean quit so it does not accumulate in project directories.
  Off with `vim.g.envup_session = false`.
- New global gitignore at `~/.config/git/ignore` (a path git reads on its own,
  no `core.excludesFile` to get wrong) covering `Session.vim` and `.nvimlog`,
  for the crash that leaves one behind in a repository.

### Three tools the rest of the config assumed

- **New modules: `ripgrep`, `fd`, `delta`** — all three in the `standard`
  profile. They were already being *used*: fzf lists files with `fd` when it can
  find it, nvim's Telescope greps with `rg`, and the git module has shipped a
  `[delta]` section plus pager detection since 0.2.0. Nothing ever installed
  them, so on a fresh machine each of those paths quietly took its fallback (or
  did nothing at all) and looked like the feature was just slow, or missing.
- Each is one static binary, so the no-root `github_release` route works and a
  server where you have only an account gets the same tooling as a workstation.
- **The naming, which is the whole difficulty.** The package is `ripgrep` and
  the binary is `rg`; the package is `git-delta` (except on Alpine) and the
  binary is `delta`; on Debian and Fedora the package is `fd-find` and the
  binary is `fdfind`, because Debian gave `fd` to something else first. The fd
  module links the distro's binary into `~/.local/bin/fd` on install and removes
  that link on uninstall, so `fd` means `fd` everywhere.
- Installing `delta` re-runs the git module's config generation, because git is
  installed first and therefore wrote "no delta on this machine" before delta
  existed. Without that, the pager only turned on at the *next* `envup install
  git` — which is the kind of thing you never connect to the cause.

### The editor, for the way a server actually gets used

- **Undo survives the session** (`undofile`, 10 000 levels). An SSH connection
  drops, the shell dies, nvim dies with it — and everything since the last write
  used to be gone. History goes under `stdpath("state")`, keyed by full path, so
  a home directory shared over NFS does not mix machines up.
- **A big file no longer takes the editor down with it.** Past 1.5 MB
  (`vim.g.envup_bigfile_bytes` to change it, `0` to disable) a buffer opens with
  syntax, treesitter, LSP, folding, undo and swap switched off, and says so. The
  decision is made on `BufReadPre`, before the highlighter has started, because
  by `BufReadPost` the hang has already happened. Tailing a 200 MB log over SSH
  is now boring instead of a killed terminal.
- **Format on save — but only where the project says how.** conform.nvim now
  covers lua, C/C++, python, shell, json, yaml and markdown, and runs on save
  only when the project ships the matching style file (`.clang-format`,
  `stylua.toml`, `pyproject.toml`, …). Unconditional formatting means your first
  save in someone else's repository reflows the whole file to LLVM style and the
  diff is yours to explain. `<leader>fm` still formats anything on demand;
  `vim.g.envup_format_always = true` opts into the unconditional behaviour, and
  `vim.b.disable_autoformat` / `vim.g.disable_autoformat` opt out. No LSP
  fallback — that is the same surprise from a different binary.
- conform is loaded on `BufWritePre` rather than lazily on some later event,
  without which `format_on_save` was simply never consulted.
- **Diagnostics you can read.** `]d` / `[d` move between problems and open the
  full text in a float on arrival (`<leader>df` for the one under the cursor) —
  the virtual text at the end of the line is truncated at the screen edge, and a
  clangd template error does not fit. Nothing appears while you are still
  typing. Both the 0.10 (`goto_next`) and 0.11 (`vim.diagnostic.jump`) APIs are
  handled, since the NvChad pin here still supports 0.10.

### A `TERM` that matches the machine

- **`default-terminal` is `tmux-256color` where the entry exists, and
  `screen-256color` where it does not.** It was unconditionally the latter,
  which costs italics and makes tmux describe itself as something it is not.
  Setting it unconditionally the other way is worse: ncurses added
  `tmux-256color` in 6.0, and on a CentOS 7-era box naming a terminfo entry that
  is not installed breaks colours *and* the Home, End and arrow keys.
- Decided at server start by `infocmp`, so one config is right on both. Missing
  `infocmp` — the slim container images drop `ncurses-bin` — takes the safe
  branch quietly rather than printing `command not found` over your first
  screen. `tmux show -s default-terminal` says which one you got.
- The `Tc` truecolor override still globs on `*256col*`, which both names match.
- The case the probe cannot see is an old machine you `ssh` *to* from inside
  tmux: it inherits this `TERM`. Pin `screen-256color` in that machine's
  `hosts/<hostname>.conf`. See [docs/TMUX.md](docs/TMUX.md).

### Project switching

- **`prefix f` / `ts`** — fzf over your project roots, then attach-or-create a
  tmux session named after the project, so picking one you already have open
  takes you back to it. `modules/tmux/files/bin/tmux-sessionizer`, linked to
  `~/.local/bin`.
- Roots come from `~/.config/envup/project-dirs` (one glob per line) with six
  sensible defaults, so most machines need no configuration. A file rather than
  an environment variable because a tmux key binding runs under the tmux
  server's environment, which never sourced your `.zshrc`.
- The `ts` shortcut is only defined when nothing else on the machine is called
  `ts` — moreutils ships one.
- **The picker opens in a popup** over the current pane on tmux 3.2 and up:
  nothing in your layout moves, and cancelling leaves nothing behind. Older tmux
  keeps the throwaway window. `prefix f` now runs `tmux-sessionizer --launch`,
  which asks the running server its version and opens the right one — so
  upgrading tmux is enough by itself, and the decision is testable in a way an
  `if-shell` condition in the config never was. Unparseable versions (OpenBSD
  reports `openbsd-7.4`) read as old. Override with
  `tmux set-environment -g ENVUP_TS_POPUP 0` / `1`.

### Three more tools the config was already calling

- **New modules: `eza`, `bat`, `direnv`** — all three in the `standard` profile.
  Same shape as the ripgrep/fd/delta gap: the zsh module has pointed `ls`, `ll`,
  `la` and `tree` at eza and `cat` at bat since 0.2.0, each behind a
  `(( $+commands[...] ))` guard, and 50-tools.zsh has run `direnv hook zsh`
  whenever the binary existed. Nothing installed any of them, so the guards were
  false on every machine and the aliases silently stayed as the system's.
- **bat has two names**, exactly like fd: Debian had already given
  `/usr/bin/bat` to bacula, so its package installs `batcat`. The module accepts
  either name and links a `bat` shim into `~/.local/bin`, removed on uninstall.
- **eza publishes two builds per platform** and one of them is `_no_libgit` —
  the same program with `--git` compiled out, which is the flag `ll` passes. The
  two are indistinguishable by score, so which one you got came down to `sort`'s
  collation and therefore to `$LC_COLLATE`. New `GH_ASSET_AVOID` in the
  github_release provider settles it: a penalty, not a veto, so a platform where
  the reduced build is the only asset still installs.
- direnv is a bare binary rather than an archive (the provider already handled
  that) and one Go build with no libc variants, so it works on the old-glibc
  machines where the Rust tools need their musl asset.
- `GH_TREE` and `GH_ASSET_AVOID` are now reset between modules. The engine loads
  them into globals in one process; `GH_TREE` was never cleared, so a module
  installed after nvim would have been treated as a directory tree.

### Downloads that are what the release says they are

- **`github_release` now verifies what it downloaded.** The provider already
  filtered `.sha256` / `.sha512` / `checksums.txt` out of the asset candidates —
  correctly, they are not the binary — but then discarded them. Now it looks for
  the digest that covers the chosen asset (sidecar first, then the release-wide
  manifest under any of the names goreleaser, neovim and fzf give it) and
  compares before unpacking.
- **What this is and is not worth.** The digest is published in the same release
  and fetched over the same link, so it says nothing about an upstream that was
  compromised or a mirror that is actively hostile — either can serve a matching
  pair. It catches the ones that actually happen: a corporate proxy answering
  200 with a captive-portal page, a transfer truncated where the link dropped, a
  mirror a week stale handing back the previous release. All three used to
  install without a word and fail later, somewhere with no visible connection to
  the download.
- **Missing digests are not fatal by default.** fd, bat and delta publish none;
  refusing them would trade a working install for a guarantee that isn't on
  offer. The skip is a debug log line. `ENVUP_REQUIRE_CHECKSUM=1` makes it a
  refusal instead — the setting for when `ENVUP_GH_MIRROR` points at a proxy you
  don't operate.
- Digests are computed with whichever of `sha256sum` / `shasum` / `openssl` the
  machine has, since no single one is everywhere: coreutils is absent from a
  stock macOS, `shasum` from slim Linux images. A machine with none of the three
  reports that it cannot check rather than passing the file.

### An uninstall that actually gets back to where it started

- **`uninstall --all` no longer leaves an empty `~/.bashrc` behind.** On a home
  that had no `~/.bashrc`, the zsh module has to create one before it can write
  the `exec zsh` shim into it. Removing the shim left the file at 0 bytes —
  reversible with an asterisk on it. `block_set` now records the files it
  brought into existence (in `$ENVUP_STATE_DIR/created`, beside the manifest,
  because that is a fact about the machine and not about the repo two machines
  share) and `block_del` reclaims one only if envup created it *and* it is empty
  again. A `~/.bashrc` you already had, or that you have since written to, is
  left exactly as it is — "delete any empty file" would have broken the same
  guarantee from the other side.
- **Directories that only existed to hold a symlink are given back.** A real
  install created `~/.config/git`, `~/.tmux/plugins` and `~/.local/bin`; an
  uninstall removed the links inside them and left three empty directories.
  `unlink_safe` now prunes the chain it linked into, and `engine_uninstall`
  does the same for `~/.local/bin`. The mechanism is `rmdir`, which refuses a
  directory with anything at all in it — so a `~/.local/bin` holding a binary
  envup installed, or a `~/.config/git` holding a file you wrote, is untouched.
- Still deliberately kept: system packages, binaries in `~/.local/bin`, the
  `chsh` setting, `~/.gitconfig.local`, `~/.oh-my-zsh`, and everything under
  `~/.dotfiles_backup/`.

### `envup upgrade` says why it couldn't update the source

- **The failure that this design produces most often is now diagnosed by name.**
  Configs are symlinks *into* the checkout, so the working tree is in daily use
  and a tool that appends to `~/.zshrc` is appending to a tracked file. Every
  such case used to print one line — "git pull failed — source NOT updated" —
  which is true, identical for a dozen different causes, and hands you back to
  bare git. `envup upgrade` now names the managed files that were edited in
  place and points at `envup adopt`, lists other uncommitted changes separately
  with `git stash`, and reports a branch with no upstream or a directory that
  is not a git checkout as themselves.
- **A detached HEAD is caught before the network call.** `envup upgrade --ref
  v0.2.0` leaves HEAD detached by design, and every plain `envup upgrade` after
  it fails forever. That one is certain rather than likely, so it is checked
  locally — with `envup upgrade --ref main` given as the way back — instead of
  spending the fetch timeout to find out.
- **Plugin submodules at a newer commit are not dirt.** They move whenever a
  plugin updates; counting that as pollution would make every machine with
  up-to-date plugins unupgradable.
- The diagnosis runs *after* git has spoken, not instead of it: a dirty tree
  only fails a pull that would have to overwrite the dirty file, so pre-refusing
  would block upgrades that were going to work.
- `tests/unit/upgrade.bats` — 17 cases against a real local origin and clone.
  Nothing about git is stubbed, because telling a dirty tree from a detached
  HEAD from a missing upstream is the entire thing being tested. Previously two
  files mentioned the command at all.

### A wrong command line, a proxy, and a half-finished download

A pass over the paths that only run when something is already going wrong — the
ones you never exercise on the machine you developed on.

- **No option can hang.** `envup upgrade --profile` with the value left off spun
  forever: `shift 2` with a single argument remaining fails *without shifting*,
  so `while (($#))` never advanced. envup's headline promise is that no step can
  hang the whole run, and every network call is time-boxed to keep it — which
  was worth very little while the argument loop could eat the process before any
  of that machinery started. Every value-taking option now checks its value is
  there and says which option is missing it. `tests/unit/cli.bats` runs the whole
  option table under `timeout` so an option added later is covered by adding a
  line to a list.
- **A misspelt option is refused, not ignored.** `envup status --jsonn` printed
  the human table, which is the worst available answer for a script that asked
  for JSON; `envup clean --dry-runn` reported "no module: dry-runn", which sends
  you looking for a module instead of at the flag you mistyped. `status`, `log`
  and `clean` now name the unknown option.
- **`ENVUP_GH_MIRROR` rewrites GitHub's hosts and nothing else.** Every URL in
  the codebase goes through `gh_url` — that is the single-door design — and the
  prefix was unconditional, so a vendor's own installer (atuin's
  `https://setup.atuin.sh`) became `https://mirror/https://setup.atuin.sh` on
  exactly the machines that need a mirror most. A GitHub proxy cannot serve a
  host it has never heard of. The rewrite is now scoped to the six hosts a
  GitHub proxy actually fronts, matched on the full host so
  `github.com.evil.example` doesn't qualify, and `tests/unit/ghurl.bats` sweeps
  every URL in `modules/*/meta.sh` to check each one is either left alone or
  rewritten onto a real GitHub host.
- **Backups keep the path they came from.** `$ENVUP_BACKUP_DIR` was keyed by
  basename, so two link targets sharing one — a module adding
  `~/.config/foo/config` next to `~/.config/bar/config` is all it takes — had the
  second backup overwrite the first, and the user's file was gone with no
  message. That is backup-never-clobber failing at the one job it has. Backups
  now mirror the original path under the timestamped directory (paths outside
  `$HOME` under `root/`), which also restores the other thing a backup is for:
  telling you where the file came from, months later, from the backup alone.
- **A tree install that fails leaves the previous version in place.** The
  `GH_TREE` route did `rm -rf "$dest"` and *then* `mv`, and that `mv` crosses
  filesystems — temp dir to `$HOME`, where mv does real copying and can run out
  of space. A failure there left the working install deleted and nothing in its
  place. It now stages beside the destination and swaps, restoring the old tree
  if the swap fails: an upgrade cannot end with less than it started with.
- **A release that drops a binary no longer leaves a dangling symlink on PATH.**
  The previous version's link stayed, pointing into the tree that was just
  replaced. That is worse than a missing command: `command -v` finds it, `envup
  status` calls the module installed, and the exec fails naming a file that is
  right there. Links into the module's own tree that no longer resolve are swept
  after each install; links pointing anywhere else are left alone.
- **`doctor` and `adopt` write a log.** `--fix` rebuilds links and drops manifest
  orphans; `adopt` moves content between files and runs `git checkout --`. Every
  other command that changes the machine left a timestamped log, and for a long
  time the two repair commands — the ones you most need to explain afterwards —
  were the exceptions. Logging starts after argument parsing, so `--help` still
  writes nothing.
- **`$ENVUP_STATE_DIR` honours `XDG_STATE_HOME`,** but never at the cost of
  losing state already on disk: a machine already using `~/.local/state/envup`
  keeps using it, so setting the variable later can't make an installed
  environment look uninstalled.
- **`envup upgrade --ref` completes tags and branches.** Pinning or rolling back
  a release is the reason the flag exists, and the completion offered no values,
  so you had to know the tag name by heart. It now reads them out of the
  checkout. `tests/unit/cli.bats` also checks every long option each parser
  accepts is offered by `completions/_envup`, against the parsers themselves
  rather than a list somebody has to remember to update.
- **`doctor --authoring` catches two more mistakes.** A misspelt contract field
  (`VERIFY_MIN_VER`) used to be a variable nothing reads and no error — the
  module simply had no version floor. And two modules can no longer both claim
  the same `LINKS` destination, where the second install would silently take the
  file from the first. The field list is read out of `_engine_load` rather than
  copied, because a hand-synced copy goes stale in both directions: a new field
  reported as a typo, and a typo accepted as a field.

### `status` says which kind of link problem it is

- **`! module — 2 broken link(s)` was wrong most of the time it appeared.**
  Three different situations were counted together: a link that does not exist
  yet, a link that dangles, and a path already occupied by a file of your own.
  The common one by far is the first — you pull a repo that grew a new helper
  script or config file, and the machines that have not re-installed report it —
  and there is nothing broken about it. It now reads `2 links not created yet`,
  `1 dangling link` or `1 path already in use`, listed together when a module
  has more than one kind, and a run with any of the first prints the command
  that fixes it. The legend calls `!` *needs attention* rather than *broken*.
- **`status --json`: `broken_links` is replaced by `link_issues`**, an object of
  `{unlinked, dangling, foreign}`. The old field's number is still the sum, but
  it is a rename rather than a redefinition on purpose: a consumer reading
  `.broken_links` now gets nothing instead of a number that quietly means
  something else.
- `doctor` already named each link and its state; only `status` collapsed them.

### Every downloadable tool is pinned

- **`versions.lock` covers all ten `github_release` modules**, not four. ripgrep,
  fd, delta, bat, eza and direnv were taking whatever was latest on the day each
  machine was set up — so the fleet agreed about fzf, zoxide, atuin and nvim and
  quietly disagreed about the rest. A half-pinned fleet is worse than an unpinned
  one: the tools that differ between two servers are the ones nobody chose, and
  nothing in `status` says which they are.
- **`tests/unit/providers.bats` now checks the file, not just the mechanism.**
  Three guards: every module whose `PROVIDERS` include `github_release` has a
  line, no line names a module that no longer installs that way, and each tag is
  shaped like a tag. The lockfile is edited by hand and nothing bumps it —
  Dependabot cannot see it — so the failure mode is a new module shipping
  unpinned and nobody noticing for a year.
- Tags are upstream's spelling, verbatim: ripgrep and delta publish `15.2.0`,
  everything else `v15.2.0`. Constructing one from a version number 404s.

### A release you can check out, from a CI you can pin

- **0.2.0 is tagged.** It had a heading, a date and a migration guide, and no
  tag — so `envup upgrade --ref v0.2.0`, the command the README gives for
  pinning a fleet to a known release, failed on the only release worth pinning
  to. The tag points at the commit that bumped `VERSION`, dated to match.
- **Every version heading in this file is now a link** to the diff that produced
  it, the way Keep a Changelog intends. They live at the bottom of the file.
- **`tests/unit/release.bats`** checks the three things that have to agree and
  that nothing else looks at: `VERSION` against the newest dated section, each
  heading against its link definition, each documented version against
  `git tag`. All three are updated by hand from a checklist, the checklist was
  followed once and missed once, and a missing tag is invisible from inside the
  repo. The tag check skips where tags aren't fetched (shallow CI checkout,
  source tarball) rather than failing on them.
- **GitHub Actions are pinned to commit SHAs**, version in a trailing comment. A
  tag is a movable label: whoever can push to `actions/checkout` can repoint
  `v4`, and this workflow holds a checkout of the repo and the runner's token.
  envup verifies the digest of every binary it puts on your machine; its own CI
  was the odd place to stop.
- **Dependabot** (`.github/dependabot.yml`) covers the two supply chains that
  exist here and had no update channel at all: those actions, and the git
  submodules under `modules/*/files`, whose contents are sourced into every
  interactive shell on every machine envup has touched. Submodule bumps are
  grouped — eleven PRs a month is how a bot gets muted. The downloaded binaries
  stay out of it: they're pinned in `versions.lock` and digest-checked by
  `lib/net.sh`, which Dependabot cannot see.
- **CI runs on a machine older than the CI machine.** The container matrix
  gained `debian:11` — glibc 2.31, below the 2.34 that current prebuilt binaries
  are built against. That is the failure envup exists to survive — a tool that
  installs perfectly and then dies on every call with a missing GLIBC symbol —
  and every other image hid it: alpine is musl, fedora and arch are both newer
  than the runner.

### The env vars that were only in the source

- **Eleven `ENVUP_*` variables are documented for the first time**, including
  the ones a locked-down machine actually needs: `ENVUP_PRIV_KEEP_ENV` (whether
  privileged commands keep your proxy through `sudo -E`), `ENVUP_BACKUP_DIR`
  (where your pre-existing dotfiles are moved before a link replaces them),
  `ENVUP_LOCAL_OPT`, `ENVUP_LOG_DIR`, `ENVUP_LOG_FILE`, `ENVUP_EDITOR`,
  `ENVUP_NET_PROBE_TIMEOUT` and `ENVUP_PLATFORM`. The README had a whole section
  on the backup guarantee without ever saying the destination could be changed.
- **`README.zh-CN.md` gained the environment-variable table** the English README
  always had; the two now name exactly the same set, which is itself checked.
- **`tests/unit/knobs.bats`** makes the gap unrepeatable. Every `ENVUP_*` name in
  the code must be either documented or listed as internal with a reason, and the
  test also catches the reverse — a variable renamed in the code while the README
  keeps advertising the old name, so the user's `export` silently does nothing.
  An env var is the one part of the interface with no signature and no caller to
  keep it honest: adding one costs nothing and tells nobody. Ten are declared
  internal (`ENVUP_RC_*`, manifest paths, the sudo argv, a test hook).

### Internals

- **`lib/upgrade.sh`** — the `git` half of `cmd_upgrade`, which had been two
  lines of error handling inside the CLI.
- **`lib/verify.sh`** — "is this tool present, runnable and new enough?" moved
  out of `engine.sh`, which was over the size budget. The seam is not just
  arithmetic: `status`, `doctor` and module hooks all ask that question without
  installing anything, and keeping it in the install engine made that easy to
  forget.
- **`scripts/lint.sh` now measures `lib/providers/*.sh` too.** They had been
  excused from the size budget as "one route each", and `github_release.sh`
  grew to within five lines of the threshold with nobody being told. A guard
  that skips files is worse than no guard, because it reads like coverage —
  `tests/unit/liblayout.bats` now asserts that every file in `lib/` appears in
  lint's output and that `lib.sh` sources each one by name.
- **Asset integrity moved from `lib/providers/github_release.sh` to
  `lib/net.sh`** as `net_sum_url` / `net_check_asset`. Checksum discovery and
  verification is a property of downloading a file, not of one provider, and
  leaving it there meant the next provider that fetches an artifact would either
  reach across into another provider's private helpers or grow its own copy.
- **`log_init` and `$ENVUP_STATE_DIR` have one definition each.** `log_init`
  existed identically in `envup` and `lib/log.sh`; whichever the reader found
  first was the one they'd edit. `$ENVUP_STATE_DIR` was defined in
  `lib/manifest.sh`, which loads after `lib/fs.sh` needs it.
- **`tests/unit/cli.bats`** — the dispatcher's argument handling had no tests at
  all, which is how a hang lived in the option loop.

### Fixed

- **`envup install` no longer calls a helper that was deleted.** `pkg_have`
  was a duplicate of `have`, removed when the library was deduplicated; one
  caller in the CLI was missed, so every install printed
  `envup: line 93: pkg_have: command not found` once per module and — because
  the failed call is the one deciding whether a prerequisite is already
  present — the answer was always "missing". Every run therefore called the
  package manager for packages the machine already had, which on a sudo-capable
  Debian box meant an `apt-get update` and an unasked-for upgrade of `curl`.
  Nothing checked stderr: the dry-run tests asserted exit codes and symlinks,
  and this printed on every one of them for two releases. They now fail on
  `command not found`, `unbound variable` or `syntax error` from any profile,
  and the read-only commands are held to the same rule.
- **`.gitconfig` no longer names binaries it cannot guarantee.** `core.editor =
  nvim`, `merge.tool`/`diff.tool = vimdiff` and `interactive.diffFilter = delta`
  were committed unconditionally and read on every machine. On a box without
  them that meant a broken `git commit`, a broken `git mergetool`, and — worst —
  a `git diff` that piped into a missing binary. The editor now comes from
  `30-env.zsh`'s runtime detection, and delta is enabled only where it exists,
  via a generated `~/.gitconfig.envup` rewritten on every install and removed on
  uninstall.
- **`doctor --authoring` no longer warns about optional link sources.** It
  stripped the `?` and then checked the file existed anyway, so a
  `hosts/<hostname>` link produced a warning on every machine that wasn't that
  one. A missing optional source now logs at info level in `_link` too — absence
  is a fact there, not a fault.
- **A module's `GIT_SETUP` no longer leaks into the next one.** `_engine_load`
  reset every other contract field between modules but not this one, so a module
  using the git provider after fzf would run fzf's setup command.
- **`version_ge` no longer reads "0.9" as older than "0.9.0".** A trailing zero
  component carries no information, but `sort -V` orders the shorter string
  first — so a tool that reports two components against a three-component floor
  was declared too old and reinstalled on every run.
- `scripts/lint.sh` now covers `modules/*/files/bin/*`.
- Added `docs/TMUX.md`, referenced from the README since 0.1.0 but never
  written.

## [0.2.0] - 2026-08-15

A cross-platform correctness release. 0.1.0 got the engineering shell right
(tests, CI, versioning) but never touched runtime behaviour on the machines that
matter: servers without root, restricted networks, home directories shared over
NFS, macOS and Linux side by side. This release rebuilds the module contract and
the shell config model around those.

**This release contains breaking changes.** See *Migrating from 0.1.x* below.

### Machines without root

- **Module contract v2.** `meta.sh` is now pure declarative data; the install is
  driven by an engine (`lib/engine.sh`) with five pluggable providers
  (`system`, `github_release`, `git`, `script`, `manual`). Modules declare an
  ordered fallback chain and the engine picks the first route that works here.
- **`github_release` provider** downloads prebuilt binaries into `~/.local/bin`,
  matching assets against the detected OS / arch / libc — including choosing a
  musl build when the host's glibc is too old — and pinning versions in
  `versions.lock`. This is what makes a no-sudo server usable.
- **Four install outcomes** — `ok` / `degraded` / `skipped` / `failed` — with a
  per-module reason. A tool that can't be installed here still gets its config
  linked (`degraded`) and starts working the moment the package appears. Only
  `failed` is a non-zero exit.
- **One module's failure no longer aborts the run.** Missing prerequisites are
  advisory; previously any `SELF_DEPS` failure stopped every profile dead on a
  machine without root.
- **Privilege detection via `sudo -n true`.** A `sudo` that exists but wants a
  password is treated as no privilege at all, instead of blocking a
  non-interactive install until the 900s watchdog killed it.
- Cross-distro package names (`PKG_NAMES`), so `fd`→`fd-find` and friends are
  expressible.

### Restricted networks

- **All network egress goes through `lib/net.sh`.** `ENVUP_GH_MIRROR` and the new
  `ENVUP_OFFLINE=1` now cover releases, clones and vendor install scripts alike —
  including atuin's installer, which previously bypassed the mirror entirely.
  `doctor --authoring` rejects a module that calls `curl`/`wget`/`git clone`
  directly.
- **Proxy variables survive privilege escalation** (`sudo -E` when a proxy is
  set); `sudo`'s `env_reset` used to strip them and break `apt-get` on every
  corporate network.
- A failed `apt-get update` is no longer recorded as a success.

### Shell behaviour

- **Config slices are numbered and reordered.** `20-platform` now runs *before*
  `50-tools`, fixing the bug where every Homebrew-installed tool (zoxide, atuin,
  fzf) silently failed to initialise on macOS because `brew shellenv` hadn't run
  yet.
- **Nothing is set unconditionally any more.** `LANG` is only set to a locale the
  machine actually has and `LC_ALL` is never set; `TZ` is left alone; `EDITOR` is
  the first of `nvim`/`vim`/`vi` that exists; `alias vim=nvim` is only created if
  nvim is installed. The old behaviour broke `git commit`, `crontab -e` and every
  command's output on minimal servers.
- **PATH is built with idempotent helpers** and never reorders the inherited
  value. `.zshenv` used to prepend the system directories ahead of everything
  inherited, demoting brew / conda / HPC `module load` toolchains, and PATH grew
  without bound in nested shells.
- `compinit` runs exactly once (was twice, costing 100–300ms — worse on NFS);
  nvm is a lazy shim (was 200–800ms at startup); the WSL2 slice no longer calls
  `cmd.exe` synchronously on startup; macOS no longer overrides the eza aliases.
- **Slice errors are no longer swallowed.** A slice that fails prints which one
  and why; `ENVUP_ZSH_QUIET=1` restores the old silence.

### Multi-machine

- **New `hosts/` layer**: `~/.zshrc.d/hosts/<short-hostname>.zsh` is committed,
  so per-machine settings sync and survive a rebuild — and stay separate on a
  shared home. Private overrides moved to `~/.zshrc.local` (and
  `~/.zshrc.local.<hostname>`), **outside** the repo checkout.
- **Symlink ownership is compared both resolved and unresolved**, so a home
  automounted as `/home` → `/mnt/home` no longer makes `uninstall` refuse to
  remove envup's own links.
- **`_realpath`** falls back `readlink -f` → python3 → `cd -P && pwd -P`, correct
  on macOS without coreutils. Previously the "already linked" check was always
  false there, relinking on every run.
- **Manifest schema 2** records state, provider, version, timestamp and the repo
  root. Moving the checkout is now reported as one message instead of twenty
  dangling links, and `doctor --fix` relinks from the new location.
- **New `envup adopt`**: when a third-party installer appends itself to a tracked
  config file (reachable because `~/.zshrc` is a symlink into the repo), move
  those lines to `~/.zshrc.local` and restore the file — instead of a failing
  `git pull` on the next machine.

### Diagnosability

- **`envup doctor` now health-checks the machine** — every managed symlink, tool
  version, manifest entry, submodule, `~/.local/bin` on PATH, locale validity,
  repo drift and relocation. `--fix` repairs and then **re-checks**, so a clean
  exit means "it is fixed", not "I tried". The old module-authoring validation
  moved to `doctor --authoring`.
- Findings are split into **issues** (broken, exit 1, fixable) and **notes**
  (working as designed, exit 0) — a degraded module on a locked-down server no
  longer fails the check.
- **A tool only counts as installed if it runs.** Verification now checks the
  binary's exit status instead of scraping whatever it printed: a prebuilt
  release built against a newer glibc than the host prints ``version
  `GLIBC_2.33' not found`` and dies, and envup used to read *2.33* out of that
  message and report `ok`. Such a binary is now `broken` — a doctor issue with
  a hint to let the engine try another provider — and version strings are read
  from stdout, falling back to stderr only after a clean exit. Modules whose
  tool answers on a different flag declare `VERIFY_VERSION_ARG` (tmux: `-V`).
- **`envup status` reports what is true on disk**, re-reading every symlink and
  re-running every version check: `✓ ok` / `~ degraded` / `! broken` /
  `○ not installed`. It could previously show `✓` for a config you had deleted.
  `--json` gained `state`, `tool`, `provider`, `version`, `broken_links`, `priv`
  and `net`.
- `clean --all` no longer depends on argument order.

### Internals

- `lib.sh` split into `lib/` (`log` `caps` `fs` `net` `pkg` `manifest` `module`
  `engine` `providers/*` `health` `adopt` `authoring` `doctor`); `envup` is a
  dispatcher.
- The module watchdog re-execs `"$BASH"` rather than a bare `bash`, so macOS
  hooks keep bash ≥ 4 instead of falling back to 3.2.
- `--dry-run` is total again: `install --dry-run` on a machine without nvim no
  longer fails with a misleading `nvim too old:`.
- Test suite grew to 200+ unit tests plus integration; CI gained an unprivileged
  container job and an offline job, and installs `zsh` so the shell-config tests
  actually run.

### Migrating from 0.1.x

Breaking, in rough order of how likely you are to notice:

1. **Personal overrides moved.** `~/.zshrc.d/local.zsh` (inside the checkout,
   gitignored) is replaced by `~/.zshrc.local`. The old file is still sourced
   with a warning, so nothing is lost — move it when convenient:
   `mv ~/.zshrc.d/local.zsh ~/.zshrc.local`.
2. **Machine-specific config has a real home.** Anything in your old `local.zsh`
   that other machines should also get belongs in
   `~/.zshrc.d/hosts/$(hostname -s).zsh` (committed). Start from
   `~/.zshrc.d/hosts/example.zsh.template`.
3. **`bare envup doctor` changed meaning** — it health-checks the machine now.
   If you called it in CI to validate modules, use `envup doctor --authoring`.
4. **`LC_ALL`, `TZ` and `EDITOR` are no longer forced.** If you relied on envup
   exporting `LC_ALL=en_US.UTF-8` or `TZ=UTC`, set them yourself in the host or
   local layer.
5. **Custom modules must be ported** to the v2 contract: move `install.sh` /
   `uninstall.sh` logic into `hooks.sh` functions and describe the install in
   `meta.sh`. `envup doctor --authoring` names every leftover.
6. The manifest upgrades itself on the next install; schema 1 files still read.

There is no compatibility switch for any of the above — envup is small enough,
and used by few enough people, that carrying two code paths costs more than the
one-time move.

## [0.1.0] - 2026-07-02

First public release.

### Core

- Modular dotfiles / dev-environment manager: a thin CLI (`envup`) + a shared
  library (`lib.sh`) + pluggable modules (`zsh`, `git`, `tmux`, `fzf`, `zoxide`,
  `atuin`, `nvim`).
- Profiles `minimal` / `standard` / `full`, composed via `use_profile`.
- Safe symlinking with automatic backup, idempotent and reversible installs,
  dry-run everywhere, cross-platform package install (apt/dnf/yum/pacman/brew/apk).

### Tooling & quality

- Test suite: bats unit + integration (`scripts/test.sh`); `shellcheck` +
  `bash -n` (`scripts/lint.sh`); GitHub Actions CI matrix (lint / unit /
  integration / smoke on Ubuntu, macOS, and Fedora/Arch/Alpine containers).
- Versioning & releases: `VERSION`, `envup --version`, this changelog, and
  `envup upgrade --ref <tag|branch>` to pin/roll versions.

### Controllability

- `envup status --json` for machine-readable state.
- `ENVUP_LOG_LEVEL` (`debug`/`info`/`warn`/`error`, default `info`) controls
  terminal verbosity; the log file always records everything.

### Extensibility

- `envup doctor`: static validation of module conventions (meta fields,
  function-wrapped hooks, valid `DEPENDS`, and `CLEAN_PATHS` that never target
  user data).
- `ENVUP_GH_MIRROR`: route envup's GitHub downloads through a proxy prefix for
  restricted networks.

### Robustness

- No single step can wedge the whole run: network calls and `pkg_install` are
  wrapped in timeouts, and every module hook runs under an outer watchdog
  (`ENVUP_MODULE_TIMEOUT`, default 900s) — a stuck module is killed and reported
  failed while the install continues with the rest.
- Manifest carries a `# envup-manifest schema=1` header (old headerless
  manifests still read).

### Docs & community

- English + `README.zh-CN.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `TMUX.md`,
  issue/PR templates, `CODE_OF_CONDUCT.md`, `SECURITY.md`.

<!-- Every version heading above is a link to the diff that produced it. Keep a
     Changelog puts these at the bottom; tests/unit/release.bats checks that a
     new section never ships without one. -->

[Unreleased]: https://github.com/gendu-amd/envup/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/gendu-amd/envup/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gendu-amd/envup/releases/tag/v0.1.0
