# Agent instructions

Read `README.md` for project usage.

- AppUpdater is a remote Swift package dependency. Use a temporary local override only for package development, and remove it before verifying a release.
- Follow the existing Swift and SwiftUI patterns; keep changes focused and maintainable.

## Releases

Before preparing or publishing a release, read [RELEASING.md](RELEASING.md) and `.release.json`. Use an explicit version with no `v` prefix, write curated changelog notes, preserve history, prepare required version files/assets, and commit only intended changes. Use `python3 scripts/release.py X.Y.Z --dry-run`, then the same command without `--dry-run` when a release is requested. Verify the resulting workflow and release before reporting success. Do not use Shipmark, automatic commit-based bumping, `git push --tags`, or a second GitHub release creator. Code changes alone are not a request to publish.
