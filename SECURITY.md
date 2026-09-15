# Security Policy

## Supported versions

envup is a small, single-user CLI. Security fixes land on the latest `main` /
newest release. Please run a recent version before reporting.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Instead, use GitHub's private **[Report a vulnerability](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)**
flow (Security tab → Report a vulnerability), or contact the maintainer directly.

Please include:

- affected version (`envup --version`) and OS/distro,
- a description and, ideally, a minimal reproduction,
- the impact you foresee.

We aim to acknowledge reports within a few days and will coordinate a fix and
disclosure timeline with you.

## Scope notes

envup runs installers from upstream projects (oh-my-zsh, fzf, zoxide, atuin,
lazy.nvim) and symlinks configs into `$HOME`. It never overwrites a real file
without backing it up, and `uninstall` only removes symlinks pointing into the
repo. Network fetches are wrapped in timeouts and can be routed through a mirror
(`ENVUP_GH_MIRROR`). Reports about these behaviors are in scope.
