# 0008. XcodeGen project generation from `project.yml`

## Status

Accepted

## Context

An Xcode project's `.pbxproj` file is a generated, XML-adjacent, largely
hand-unreadable artifact that Xcode itself owns and rewrites. It is also
notoriously merge-conflict-prone in team settings: two branches each adding a new
file to the same group produce a `.pbxproj` diff that Git cannot auto-merge
sensibly, and resolving the conflict requires understanding `.pbxproj`'s internal
object-graph format rather than ordinary line-based diffing.

Astra Style's repository is intended to be built and modified extensively by AI
coding agents (§0's document purpose lists Claude Code, Grok Build, Cursor, Codex,
Gemini) as well as human engineers, per file/directory operations described
throughout the spec (§8's `AstraStyle/` tree). The repo already ships a
`ios/project.yml` and `ios/Config/*.xcconfig` files rather than a checked-in
`.xcodeproj`.

## Decision

Generate the Xcode project from `ios/project.yml` using XcodeGen. The `.xcodeproj`
directory is build output: it is `.gitignore`d, regenerated on demand
(`xcodegen generate`), and never committed. `project.yml` — a declarative,
line-diffable YAML file describing targets, schemes, build settings references
(pointing at the `.xcconfig` files), and source groups — is the source of truth for
project structure and is the file that gets code-reviewed.

## Consequences

### Positive

- File additions/removals and target/scheme changes become ordinary YAML diffs in
  pull requests — a reviewer can read exactly what changed in `project.yml` without
  needing `.pbxproj` archaeology, and two branches adding different files rarely
  produce an unresolvable conflict.
- Because new source files under a folder are typically picked up automatically by
  XcodeGen's directory-based source globbing, an AI coding agent (or a human) can
  add a new Swift file to `Features/Closet/Views/` and have it appear in the Xcode
  target on the next `xcodegen generate`, without manually editing project
  membership through Xcode's UI — this matches how these agents actually operate
  (writing files directly) far better than a workflow that requires opening Xcode
  to register a new file.
- `project.yml` centralizes target/scheme/build-setting configuration in one
  reviewable file instead of scattering it across Xcode's UI-driven project
  inspector panels, which have no diff or review story at all.
- Consistent, reproducible project state across every contributor's machine and CI:
  nobody's local Xcode session can leave stray, uncommitted `.pbxproj` drift (scheme
  order, "recently used" settings, autolayout warnings toggles) that silently
  diverges from what CI builds.

### Negative (real costs, named)

- **Real Xcode-native workflow friction.** Contributors used to opening Xcode,
  dragging in a file, and clicking "Add Target Membership" have to instead either
  remember to run `xcodegen generate` after structural changes, or rely on a file
  landing in a globbed directory correctly. Forgetting this step after, say, adding
  a new Swift Package dependency or a new target produces a confusing
  "it's not in the project" experience that is not how most iOS engineers expect
  Xcode to behave.
- **Any structural change made *inside* Xcode's UI (new file group organization,
  build setting tweaks via the inspector, a new target added by the wizard) is
  silently lost on the next regeneration** unless it is also reflected back into
  `project.yml` by hand. This is a real trap for anyone unfamiliar with the
  convention — they will make a change, see it work locally, and lose it (or
  produce a confusing mismatch between their working copy and what CI builds) the
  next time someone regenerates.
- Adds a build-tool dependency (XcodeGen itself, plus whatever installs it —
  Homebrew, Mint, or a vendored binary) that every contributor and CI runner must
  have available before the project even opens; a fresh clone does not open in
  Xcode until `xcodegen generate` has been run once, which is an extra onboarding
  step compared to a checked-in `.xcodeproj`.
- Certain advanced or one-off Xcode project configurations (highly custom build
  phases, certain complex per-file compiler flag overrides, some fine-grained scheme
  behaviors) are more awkward to express in XcodeGen's YAML schema than by clicking
  through Xcode's inspector, and occasionally require falling back to a raw
  `preBuildScripts`/`postCompileScripts` shell escape in `project.yml` rather than a
  clean declarative setting.
- Xcode version upgrades occasionally change `.pbxproj`'s expected format/object
  versions; XcodeGen must keep pace with those changes, which means an XcodeGen
  version bump is sometimes a prerequisite to opening the project cleanly in a newer
  Xcode — one more version compatibility matrix (Xcode version × XcodeGen version)
  to track.

## Alternatives Considered

- **Commit the `.xcodeproj`/`.pbxproj` directly, edited through Xcode's UI.**
  Rejected: the merge-conflict and diff-unreadability problems above are worse for a
  repository expected to receive frequent, possibly-concurrent AI-agent-authored
  changes than for a small, low-churn human team; a generated project is a better
  fit for this repo's actual contribution pattern.
- **Tuist** (a more full-featured Swift-based project generator with a plugin/module
  graph system). A credible alternative offering more powerful module graph
  modeling; not chosen because the app is a single-target, feature-first-folder
  structure (§8) rather than a multi-module SPM graph today, so Tuist's extra
  capability (dependency graph modeling across many local Swift packages) is not
  needed yet. Revisit if the `Features/` folders are ever split into separate local
  Swift packages with real inter-module dependency constraints to enforce.
- **Bazel/other hermetic build systems.** Rejected as substantial overkill for a
  single-app iOS project at this stage; the operational cost (build-file authoring,
  toolchain setup, Xcode integration friction) far exceeds the benefit for a
  single-target app.
