# twitch-tag-mp3

When you record or archive Twitch streams using [yt-dlp](https://github.com/yt-dlp/yt-dlp),
you end up with MP3 files whose names encode everything worth knowing — the streamer, the date,
the time, the stream ID — but whose ID3 tags are completely blank.  Blank tags mean your music
player, media server, or NAS cannot sort, browse, or display the recordings correctly.

**twitch-tag-mp3 fixes that.**  It reads the structured filenames that yt-dlp produces and
writes proper ID3v1/v2 tags directly into the MP3 files:

| Tag | Value |
|-----|-------|
| Artist | The streamer's display name (normalised from their Twitch handle) |
| Album | `<Artist> on Twitch` |
| Track | The stream timestamp, used as a unique title |
| Year | The year the stream took place |
| Comment | A provenance note pointing back to this tool |

## Filename formats understood

```
ArtistHandle (type) YYYY-MM-DD HH_MM-StreamID.mp3
YYYY-MM-DD-HH-MM-SS-artisthandle.mp3
```

Artist handles are normalised automatically: underscores become spaces, noise words like
`Official`, `Music`, and `dj` are stripped, and a growing table of known Twitch handles maps
to the DJ or artist's real display name.

Files are processed concurrently — one child process per file, up to the limit set by
`--jobs` — so large collections tag quickly.  Synology NAS index directories (`@eaDir`) are
skipped automatically when recursing.

## Usage

```
twitch-tag-mp3 --directory <DIR> [--force] [--help] [--jobs <N>] [--json] [--noop] [--recursive] [--verbose] [--version]
twitch-tag-mp3 -d <DIR> [-f] [-h] [-j <N>] [-J] [-n] [-r] [-v] [-V]
```

Add MP3 ID3 tags to a file downloaded from Twitch using yt-dlp

| Option | Short | Description |
|--------|-------|-------------|
| `--force` | `-f` | Rewrite tags even when already up to date |
| `--help` | `-h` | Display this usage information and exit |
| `--jobs <N>` | `-j <N>` | Allow parallel I/O (default 1) |
| `--json` | `-J` | Structured output for front-end processing |
| `--noop` | `-n` | Preview the tags which would be written without modifying any files |
| `--recursive` | `-r` | Descend into subdirectories |
| `--verbose` | `-v` | See verbose progress and tag information |
| `--version` | `-V` | Print the version number and exit |

## Experimental features

```sh
EXPERIMENTAL_PROGRESS=1 twitch-tag-mp3 -d <DIR> ...
```

Setting the `EXPERIMENTAL_PROGRESS` environment variable enables size-weighted progress
percentages.  Instead of advancing by an equal step per file, each file contributes weight
proportional to its size on disk, so large files move the percentage more than small ones.
Feedback welcome.

## Dependencies

- [`id3v2`](https://id3v2.sourceforge.net/) — command-line ID3 tagger
