# picolibc-bsd

A redistribution of [picolibc](https://github.com/picolibc/picolibc) with all copyleft-licensed
files removed.

See the [upstream README](README.upstream.md) for picolibc documentation.

## Why this fork exists

Picolibc is a lightweight C library for embedded systems. The core library sources are permissively
licensed (BSD-3-Clause and similar), but the upstream repository includes a small number of
copyleft-licensed files:

- `test/` directory - GPLv2+ test suite files
- `scripts/GeneratePicolibcCrossFile.sh` - AGPLv3+ build helper
- `COPYING.GPL2` - GPL license text

These files are not needed to build or use picolibc, but their presence in git history can
complicate license compliance for projects that vendor picolibc as a submodule or dependency.

This fork provides a clean tree containing only permissively-licensed files, suitable for embedding
without copyleft concerns.

## History structure

The first commit in this repository is the unmodified upstream picolibc at the base version tag. The
second commit removes copyleft files and adds fork tooling. Future upstream updates are
cherry-picked one commit at a time with copyleft files filtered, preserving individual commit
granularity.

## Updating from upstream

Updates can be triggered manually via the
[Update from Upstream](.github/workflows/update-upstream.yml) GitHub Actions workflow, which takes
an upstream version tag (e.g., `1.9.0`) as input. The workflow:

1. Detects the current base version from the latest `*-bsd` tag
2. Runs `scripts/import-upstream.sh` to cherry-pick upstream commits with copyleft files filtered
   out
3. Opens a PR for review
4. On merge, a `<version>-bsd` tag and GitHub release are created automatically

### Manual import

To import locally instead of using the workflow:

```bash
scripts/import-upstream.sh <from-tag> <to-tag>
# e.g., scripts/import-upstream.sh 1.8.11 1.9.0
```

After importing, tag the result and push:

```bash
git tag <to-tag>-bsd
git push origin main --tags
```

## License scanning

This repository uses [scancode-toolkit](https://github.com/aboutcode-org/scancode-toolkit) in CI to
verify that no copyleft-licensed files are present. See `.github/workflows/license-check.yml`.

## License

All source code files in this repository are under permissive licenses (BSD-3-Clause, BSD-2-Clause,
MIT, ISC, and similar). The `COPYING.picolibc` file contains a license inventory that references
copyleft licenses for documentation purposes - those files have been removed from the tree. See
`COPYING.picolibc` for per-file license details.

## Attribution

picolibc is created and maintained by Keith Packard and contributors. See the
[upstream repository](https://github.com/picolibc/picolibc) for full contributor history.
