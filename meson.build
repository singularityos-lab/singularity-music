project('singularity-music', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-music"', language: 'c')
subdir('po')

gnome = import('gnome')
cc    = meson.get_compiler('c')

gtk_dep         = dependency('gtk4')
gee_dep         = dependency('gee-0.8')
gst_dep         = dependency('gstreamer-1.0')
gst_tag_dep     = dependency('gstreamer-tag-1.0')
gst_pbutils_dep = dependency('gstreamer-pbutils-1.0')
soup_dep        = dependency('libsoup-3.0')
math_dep        = cc.find_library('m')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-music-resources',
  'resources/dev.sinty.music.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: now_playing_ui
)

sources = files(
  'src/main.vala',
  'src/music_window.vala',
  'src/now_playing_page.vala',
  'src/mpris_exporter.vala',
  'src/mini_player.vala',
  'src/gst_audio_player.vala',
  'src/playlist.vala',
  'src/track_info.vala',
  'src/library_search.vala',
  'src/music_library.vala',
  'src/player_backend.vala',
  'src/remote_backend.vala',
  'src/artwork.vala',
  'src/control_strip.vala',
  'src/media_bin.vala',
  'src/browse_page.vala',
  'src/lyrics_view.vala',
  'src/spotify_page.vala',
  'src/pipe_player.vala',
  'src/sources/local_source.vala',
  'src/sources/spotify_bridge.vala',
)

executable('singularity-music',
  sources + [resources],
  vala_args: ['--pkg', 'posix'],
  dependencies: [gtk_dep, gee_dep, gst_dep, gst_tag_dep, gst_pbutils_dep, soup_dep, dependency('gio-unix-2.0'), math_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-music-widget',
  files('widget/now_playing_widget.vala'),
  dependencies: [gtk_dep, soup_dep, gee_dep, dependency('gio-unix-2.0'), libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.music.now-playing.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/search-providers/dev.sinty.music.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.music.service.in',
  output: 'dev.sinty.music.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.music.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.music.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.music.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/icons/dev.sinty.music.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

sources_test = executable('music-sources-test',
  files('tests/sources_test.vala', 'src/music_library.vala', 'src/track_info.vala', 'src/player_backend.vala',
        'src/remote_backend.vala', 'src/sources/local_source.vala', 'src/pipe_player.vala'),
  dependencies: [gtk_dep, gee_dep, gst_dep, gst_tag_dep, gst_pbutils_dep, soup_dep, math_dep, libsingularity_dep],
  vala_args: ['--pkg', 'posix'],
)
test('music-sources', sources_test, env: ['XDG_CACHE_HOME=' + meson.current_build_dir() / 'test-cache', 'GSETTINGS_BACKEND=memory'], timeout: 120)

bridge_test = executable('music-bridge-test',
  files('tests/bridge_test.vala', 'src/sources/spotify_bridge.vala'),
  dependencies: [gtk_dep, gee_dep, dependency('gio-unix-2.0')],
)
test('music-bridge', find_program('dbus-run-session'), args: ['--', bridge_test], env: ['XDG_DATA_DIRS=' + meson.current_build_dir() / 'no-apps'], depends: bridge_test)
install_data(files(
    'data/icons/singularity-music-liked.svg',
    'data/icons/singularity-music-playlist.svg',
    'data/icons/singularity-music-album.svg',
    'data/icons/singularity-music-artist.svg',
    'data/icons/singularity-music-queue.svg',
    'data/icons/singularity-music-songs.svg',
    'data/icons/singularity-music-recent.svg',
  ),
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps')
