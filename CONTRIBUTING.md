# Contributing to envup

Keep changes small, portable, and safe on machines without root or reliable
network access. Do not add a dependency when a short Bash implementation is
enough, and do not hide an unsupported case behind a successful exit.

## Module contract

A module is discovered from `modules/<name>/`; no registry is required.

```text
modules/foo/
├── meta.sh       # declarative metadata
├── hooks.sh      # optional functions only
└── files/        # optional files linked into HOME
```

Minimal example:

```bash
#!/bin/bash
# shellcheck disable=SC2034
NAME="foo"
DESCRIPTION="What the user gets"
DEPENDS=()
VERIFY_BIN="foo"
PROVIDERS=(system github_release)
GH_REPO="owner/foo"
LINKS=()
CLEAN_PATHS=()
```

Common fields:

| Field | Meaning |
|---|---|
| `NAME`, `DESCRIPTION` | identity and status text |
| `DEPENDS` | envup modules installed first |
| `SELF_DEPS` | external commands needed during installation |
| `PROVIDERS` | ordered fallback chain |
| `PKG_NAMES`, `PKG_DEFAULT` | cross-family package names |
| `GH_REPO`, `GH_TAG`, `GH_BINS`, `GH_TREE` | GitHub release settings |
| `GIT_URL`, `GIT_DEST`, `GIT_SETUP` | Git provider settings |
| `SCRIPT_URL` | vendor script provider URL |
| `VERIFY_BIN`, `VERIFY_MIN_VERSION`, `VERIFY_VERSION_ARG` | health criterion |
| `LINKS` | `repo/source:absolute/target`; prefix optional links with `?` |
| `APPLIES_IF` | condition; false means skipped |
| `CLEAN_PATHS` | disposable caches only, never config or user data |

Provider preference is normally `system`, then a portable user-space release,
then Git/vendor script, then `manual`. Put all downloads through the provider
and `lib/net.sh`; module hooks must not call curl, wget, or git clone directly.
Pin GitHub versions in `versions.lock` unless compatibility requires `GH_TAG`.

`meta.sh` must contain data only. Optional `hooks.sh` may define
`pre_install`, `post_install`, `pre_uninstall`, `post_uninstall`, or `verify`.
Never execute work at source time.

## Design rules

- Preserve existing files with `safe_link`; remove only links accepted by
  `unlink_safe`.
- Every operation must support dry-run and avoid interactive prompts.
- `degraded` is valid when config is usable but the tool cannot be installed;
  reserve `failed` for actual breakage.
- Keep Bash 4.0 compatibility. In particular, an empty array under old Bash and
  `set -u` must use `${array[@]+"${array[@]}"}` when expanded.
- Keep per-machine shareable settings in host templates and secrets in HOME
  local overrides. Never commit a real hostname, credential, cache, or log.
- Add comments only for safety, compatibility, or behavior that is not clear
  from the code.

## Checks

Install shellcheck and bats, then run:

```bash
scripts/lint.sh
scripts/test.sh
./envup doctor --authoring
./envup install --profile minimal --dry-run
./envup install --profile standard --dry-run
./envup install --profile full --dry-run
```

Tests live under `tests/unit/` and `tests/integration/`. Add a focused regression
test for behavior changes. CI also checks macOS, Linux, no-root, offline, Docker,
and Bash 4.2 paths. Do not weaken or delete a safety assertion to make a change
pass.

For a new module, verify at least:

1. Package and no-root provider selection.
2. Idempotent install and safe uninstall.
3. Missing network/tool behavior.
4. Status and doctor output.
5. Profile dry-run when the module belongs to a profile.

## Pull requests

- Keep one logical change per commit.
- Update both READMEs when commands, modules, shortcuts, or environment variables
  change.
- Update `CHANGELOG.md` for user-visible behavior.
- Leave generated config such as `.p10k.zsh`, plugin locks, and submodule sources
  intact unless the change specifically targets them.

## Releasing

1. Move release notes from Unreleased to a dated version in `CHANGELOG.md` and
   update its compare links.
2. Set `VERSION` to the same plain semantic version.
3. Run all checks above.
4. Commit and create the annotated tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
5. Push the branch and tag.

`tests/unit/release.bats` verifies agreement between `VERSION`, `CHANGELOG.md`,
and available Git tags.
