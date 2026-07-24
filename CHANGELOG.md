# Changelog

## 1.0.4 - Unreleased

- Added opt-in Metal Toolchain preparation for Apple-silicon package builds.
- Exposed the selected host Metal toolchain to opted-in Nix builds.
- Fixed sidecar generation when every requested release variant is present.
- Fixed release-sidecar access to reusable-workflow helper scripts.
- Added opt-in Linux runner disk reclamation for large Nix package builds.

## 1.0.3 - Unreleased

- Added self-contained helper checkout for reusable release workflows.
- Added strict requested-variant gating for source-owned releases.
- Added an opt-out for caller-local index rebuild dispatches.
