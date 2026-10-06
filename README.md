# Singularity Music

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

Music player for the Singularity Desktop.

- Library of the Music folder (or another folder chosen in Settings) by songs, albums and artists, with search
- Queue with shuffle and repeat, Now Playing with synced lyrics, mini player, media keys and MPRIS
- Sources from plugins: Jellyfin, Navidrome and Subsonic, Nextcloud, DLNA media servers; listens sent to ListenBrainz; lyrics from LRCLIB; missing covers from MusicBrainz (see `singularity-media-plugins`)
- A separate Spotify section: with your own Spotify developer client ID it searches the catalog and shows your library, playlists, albums, artists and queue, and plays on the Spotify device you choose (Spotify streams audio only to its own apps); without one it shows and controls the Spotify app on this computer

Accounts for the sources are added in Settings, Online Accounts. Each plugin can be switched off in Settings, Plugins, and the app options are in Settings, Apps, Music.

## Requirements

- [Meson](https://mesonbuild.com/) >= 0.59
- [Vala](https://vala.dev/) compiler
- GTK4, libgee-0.8, gstreamer-1.0, gstreamer-tag-1.0, gstreamer-pbutils-1.0, libsoup-3.0
- [libsingularity](https://github.com/singularityos-lab/libsingularity)

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## License

GPL-3.0-only, see [LICENSE](LICENSE).

## Use of Generative AI

Maintainers may use generative AI tools as assistants while working on singularity-music. Non-trivial assisted commits disclose the tool, model, and scope of the work.

AI tools may assist with code comments, documentation, repetitive code, and issue triage. Maintainers make project decisions and review every assisted change before it is merged.

Use these trailers for non-trivial assisted commits:

```plain
Assisted-by: <tool>:<model-version>
AI-Scope: <what the tool generated and the prompt or a short prompt summary>
```

Single-line completions, renames, and formatting changes do not need trailers.

Coding agents must also follow [AGENTS.md](AGENTS.md) before changing files,
creating commits, or opening pull requests.
