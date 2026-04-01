# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`twitch-tag-mp3` is a Perl utility that reads Twitch stream recording filenames (downloaded via yt-dlp) and writes ID3v1/v2 tags to the MP3 files. It processes files concurrently via forking.

## Build & Test Commands

```sh
perl Makefile.PL   # Generate Makefile
make               # Build
make test          # Run tests (parallelised by Sys::CPU)
make install       # Install
```

Debian packaging:
```sh
dpkg-buildpackage -b
```

## Architecture

**Entry point:** `bin/twitch-tag-mp3` — instantiates `Daybo::Twitch::Retag` and calls `->run($dir)`.

**Single module:** `lib/Daybo/Twitch/Retag.pm` (Moose-based) contains all logic:

- `run($dirname)` — recursively walks directories, skips `@eaDir`, forks a child for each MP3 found.
- `__tag(...)` — forks a child process; parent collects PIDs, child calls `__tagPerProcess` then exits.
- `__tagPerProcess(...)` — strips existing ID3v1/v2, writes new tags via the `id3v2` command-line utility.
- `__parseFileName($filename)` — extracts artist, album (`"$artist on Twitch"`), track (filename sans `.mp3`/suffixes), and year from the yt-dlp filename convention: `ArtistHandle (type) YYYY-MM-DD HH_MM-StreamID.mp3`. Contains hardcoded artist handle→display name mappings.
- `__acceptableDirName($name)` — returns false for `@eaDir` (Synology index dirs).

## Coding Style

All `sub` definitions must use cuddled braces — opening brace on the same line as `sub`:

```perl
sub foo {   # correct
sub foo{    # wrong
```

Subroutines prefixed with `__` are private (internal to the module). Subroutines without that prefix (`run`, `usage`) are public and form the API called from `bin/twitch-tag-mp3`.

All subroutines must be in lexical (case-insensitive alphabetical) order, ignoring the `__` prefix when determining position. This applies to new subs and any time existing subs are renamed.

## Code Quality Rules

A pre-commit hook (`maint/trap-goose-corruption.sh`, configured in `.pre-commit-config.yaml`) rejects commits if `lib/` contains:
- Markdown fences (` ``` `)
- File path headers (`### /path/file`)
- Line-number prefixes (`123: `)

**Never rewrite entire files.** Make minimal, targeted edits verifiable via `git diff`. Do not introduce formatting changes outside the scope of a requested change.

After any modification, run `git diff` and confirm only the intended lines changed. Do not commit automatically unless explicitly instructed.

## Filename Convention

Expected input filename pattern:
```
ArtistHandle (type) YYYY-MM-DD HH_MM-StreamID.mp3
```
Example: `1stdegreeproductions (live) 2021-10-18 11_05-40110166187.mp3`

`parseFileName` strips `-trim`, `-tempo`, `-untempo` suffixes from the track name and normalises artist handles (removes "Official"/"Music"/"dj", replaces `_` with space, trims whitespace, and maps specific handles to display names).
