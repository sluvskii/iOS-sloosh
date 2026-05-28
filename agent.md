# Agent Onboarding

## Workspace Overview

This workspace should be treated as centered around `neomovies-android-main/`.

- `neomovies-android-main/`: the active technical source of truth.
- `sloosh-iOS/`: removed legacy project. Do not rely on it, restore it, or use it as product guidance.

If old notes, files, or assumptions mention `sloosh-iOS`, consider them outdated unless the user explicitly says otherwise.

## Source Of Truth

Use `neomovies-android-main/` as the reference for:

- parsers
- API contracts
- repositories
- playback/source resolution logic
- downloads/offline structure
- settings behavior
- edge cases

The main goal is to preserve working technical behavior from `neomovies` while adapting it to the user's current direction.

## What Not To Assume

- Do not assume the old iOS app still matters.
- Do not spend time preserving old `sloosh-iOS` architecture or naming.
- Do not treat previous iOS onboarding notes as authoritative.
- Do not reintroduce removed legacy project files unless the user asks for them.

## Recommended Android Reference Areas

- `app/src/main/java/com/neo/neomovies/data/`
- `app/src/main/java/com/neo/neomovies/data/network/`
- `app/src/main/java/com/neo/neomovies/alloha/`
- `app/src/main/java/com/neo/neomovies/downloads/`
- `app/src/main/java/com/neo/neomovies/ui/details/`
- `app/src/main/java/com/neo/neomovies/ui/watch/`
- `app/src/main/java/com/neo/neomovies/ui/settings/`
- `app/src/main/java/com/neo/player/`

These areas are the primary technical reference when porting or rebuilding parser, API, source-selection, playback, and offline behavior.

## User Preferences

- Preferred communication language: Russian.
- Prefer minimal, verifiable edits.
- When uncertain, follow existing working behavior from `neomovies-android-main/` instead of inventing a new contract.

## Editing Guidance

- Read nearby code before changing it.
- Keep edits small and easy to verify.
- Do not revert unrelated user changes.
- If the user asks for a new implementation, use `neomovies-android-main/` for behavior and data flow reference first.

## Quick Summary

Ignore the removed `sloosh-iOS` project. For technical decisions, use `neomovies-android-main/` as the only reliable reference, especially for parsers, API behavior, repositories, playback, and downloads.
