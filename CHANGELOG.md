# Changelog

All notable changes to this project are documented in this file.

## [0.1.1] - 2026-07-11

### Fixed

- validate plugin.json version before bumping ([#9](https://github.com/mauriciovieira/skills/pull/9))
- fall back to a PR-link bullet on an all-merge-commit PR ([#9](https://github.com/mauriciovieira/skills/pull/9))
- capture PR commits before the read loop, not via process substitution ([#9](https://github.com/mauriciovieira/skills/pull/9))
- reject leading-zero version segments, force base-10 arithmetic ([#9](https://github.com/mauriciovieira/skills/pull/9))
- skip release creation if the tag's release already exists ([#9](https://github.com/mauriciovieira/skills/pull/9))

### Changed

- add release automation with bump:major/minor label override ([#9](https://github.com/mauriciovieira/skills/pull/9))

