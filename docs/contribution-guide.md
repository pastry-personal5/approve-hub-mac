# Contribution Guide

Status: Active

How to set up `approve-hub-mac`, validate a change, write commit messages, and open a pull request.

## Setup and development

- macOS with a Swift 6 toolchain (Xcode 16 or later), which provides `swift build`, `swift test` and `swift format`
- SwiftLint (`brew install swiftlint`)

```sh
swift build                                        # build the app
swift run                                          # run the app
swift test                                         # run the tests
swift format --in-place --recursive Sources Tests  # format the code
swiftlint lint --strict                            # lint with warnings treated as errors
```

## Required validation

Before opening a pull request, run the full checks from the repository root:

```sh
swift format lint --strict --recursive Sources Tests
swiftlint lint --strict
swift test
```

## Commit messages

Write commit messages in [Conventional Commits](https://www.conventionalcommits.org)
(Angular) style.

- **Title:** `<type>[(scope)]: <summary>` — lowercase, imperative, 50 characters
  or fewer, no trailing period. Types: `feat`, `fix`, `docs`, `style`,
   `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- **Body** (optional): one blank line after the title, then short paragraphs
  explaining *why* the change was made, wrapped at 72 characters. Keep it brief.

Keep each commit focused. Example:

    feat(parser): add support for nested lists

    Nested list items were flattened into a single level. Keep the nesting
    so the parsed document matches the source.

## Pull requests

TBD
