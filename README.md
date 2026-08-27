# Singularity Music

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

Music player for the Singularity Desktop.

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
