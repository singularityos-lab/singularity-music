using Gtk;
using GLib;
using Gee;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class MusicWindow : Singularity.Widgets.Window {

        private GstAudioPlayer _local;
        private PlayerBackend _player;
        private RemoteBackend? _remote = null;
        private Playlist _playlist;
        private MprisExporter _mpris;
        private GLib.Settings? _settings = null;

        private AppMediaHost _host;
        private Singularity.AppPluginHost _plugins;
        private SourceRegistry _sources;
        private LocalSource _local_source;
        private SpotifyBridge _spotify;
        private SpotifyPage? _spotify_page = null;
        private RemoteBackend? _isolated = null;
        private LocalReceiver? _receiver = null;
        private PipeAudioPlayer? _pipe = null;
        private TrackInfo? _isolated_track = null;

        private MiniPlayer? _mini = null;
        private bool _mini_mode = false;

        private Stack _root_stack;
        private MediaBin _bin;
        private BrowsePage _browse;
        private TransportStrip _transport;
        private Stack _main_stack;
        private NowPlayingPage _now_playing;
        private LyricsView _lyrics;
        private Revealer _lyrics_revealer;
        private Button _mini_btn;
        private Button _share_btn;
        private Button _back_btn;
        private Button _lyrics_btn;
        private Singularity.Widgets.WelcomePage _welcome;

        private ListBox _playlist_box;
        private Popover? _playlist_popover = null;

        private int _repeat_mode = 0;
        private uint _search_timer = 0;
        private string _browse_source = LocalSource.ID;
        private Cancellable? _resolve_cancel = null;
        private Cancellable? _lyrics_cancel = null;

        private TrackInfo? _scrobble_track = null;
        private DateTime? _scrobble_started = null;
        private int64 _scrobble_played = 0;
        private int64 _scrobble_last = -1;

        public LibrarySearch? search { get; construct; }

        public MusicWindow (Gtk.Application app, LibrarySearch? search) {
            Object (application: app, search: search);
            default_width = 1060;
            default_height = 680;
            title = _("Music");

            var source = SettingsSchemaSource.get_default ();
            if (source != null && source.lookup ("dev.sinty.music", true) != null) _settings = new GLib.Settings ("dev.sinty.music");

            _local = new GstAudioPlayer ();
            _player = _local;
            _playlist = new Playlist ();
            _mpris = new MprisExporter ();
            _mpris.start ();

            _mpris.player_obj.play_pause_requested.connect (() => _toggle_play ());
            _mpris.player_obj.next_requested.connect (() => _go_next ());
            _mpris.player_obj.previous_requested.connect (() => _go_prev ());
            _mpris.player_obj.play_requested.connect (() => {
                if (_current () != null && !_player.is_playing) _player.play ();
            });
            _mpris.player_obj.pause_requested.connect (() => {
                if (_player.is_playing) _player.pause ();
            });
            _mpris.player_obj.stop_requested.connect (() => ((GLib.ActionGroup) this).activate_action ("stop", null));
            _mpris.player_obj.seek_requested.connect ((offset) => {
                int64 pos = _player.get_position () + offset * 1000;
                _player.seek (int64.max (0, pos));
            });
            _mpris.player_obj.position_requested.connect ((pos) => _player.seek (int64.max (0, pos * 1000)));

            _host = new AppMediaHost ("dev.sinty.music", MediaKind.AUDIO, "Singularity-Music/0.1 ( https://github.com/singularityos-lab )");
            _host.attach_window (this);
            _host.message.connect ((src, text) => _toast (text));
            Artwork.get_default ().set_session (_host.session);
            var library = search != null ? search.library : new MusicLibrary ();
            if (_settings != null) {
                library.folder = _settings.get_string ("library-folder");
                _settings.changed["library-folder"].connect (() => {
                    library.folder = _settings.get_string ("library-folder");
                    library.invalidate ();
                    _browse.refresh_if_showing (LocalSource.ID);
                });
            }
            _local_source = new LocalSource (library);
            _local_source.changed.connect (() => {
                _browse.refresh_if_showing (LocalSource.ID);
                _update_welcome ();
            });
            _plugins = new Singularity.AppPluginHost ("dev.sinty.music", "music", Singularity.AppPluginHost.desktop_settings ());
            _sources = new SourceRegistry (_host, _plugins);
            _spotify = new SpotifyBridge ();

            flat = true;
            show_close = true;

            _build_ui ();
            _connect_signals ();
            _setup_actions ();

            _sources.source_added.connect (_on_source_added);
            _sources.source_removed.connect (_on_source_removed);
            _sources.add_builtin (_local_source);
            _plugins.load ();
            _host.load_accounts.begin ();
            _update_spotify_row ();
            if (_settings != null) _settings.changed["show-spotify"].connect (() => _update_spotify_row ());
            _spotify.changed.connect (() => _update_spotify_row ());

            _bin.select (LocalSource.ID, "songs");
            _browse.open_root (_local_source, "songs", _("Songs"));
            _update_welcome ();
        }

        private bool _setting (string key, bool fallback) {
            if (_settings == null || !_settings.settings_schema.has_key (key)) return fallback;
            return _settings.get_boolean (key);
        }

        private void _toast (string text) {
            add_toast (new Singularity.Widgets.Toast (text));
        }

        private void _sync_receiver () {
            if (_receiver != null && _receiver.running) {
                if (_pipe == null) {
                    _pipe = new PipeAudioPlayer (_receiver.pcm_path, _receiver.sample_rate, _receiver.channels);
                    _pipe.set_volume (_now_playing.volume);
                }
                _pipe.start ();
            } else if (_pipe != null) {
                _pipe.stop ();
            }
        }

        private string _spotify_sign_in_url = "";
        private Subprocess? _sign_in_proc = null;

        private void _sign_in_spotify () {
            string url = _spotify_sign_in_url;
            if (url == "" || _sign_in_proc != null) return;
            _spotify_sign_in_url = "";
            string? helper = Environment.get_variable ("SINGULARITY_ACCOUNTS_SIGNIN");
            if (helper == null || !FileUtils.test (helper, FileTest.IS_EXECUTABLE)) {
                helper = null;
                try {
                    string self = FileUtils.read_link ("/proc/self/exe");
                    string candidate = Path.build_filename (Path.get_dirname (Path.get_dirname (self)), "libexec", "singularity-accounts-signin");
                    if (FileUtils.test (candidate, FileTest.IS_EXECUTABLE)) helper = candidate;
                } catch (FileError e) {
                }
            }
            if (helper == null) {
                _toast (_("Sign in to Spotify in your browser to play it in Music"));
                _host.open_external (url);
                return;
            }
            try {
                var proc = new Subprocess.newv ({ helper, "--url", url, "--provider-name", "Spotify", "--provider-icon", "singularity-account-music-service" }, SubprocessFlags.NONE);
                _sign_in_proc = proc;
                proc.wait_async.begin (null, (o, r) => {
                    try {
                        proc.wait_async.end (r);
                    } catch (Error e) {
                    }
                    _sign_in_proc = null;
                    if (proc.get_if_exited () && proc.get_exit_status () == 3) _toast (_("Finish signing in to Spotify in your browser"));
                });
            } catch (Error e) {
                _toast (_("Sign in to Spotify in your browser to play it in Music"));
                _host.open_external (url);
            }
        }

        private void _on_source_added (MediaSource source) {
            if (source.id == LocalSource.ID) return;
            var receiver = source as LocalReceiver;
            if (receiver != null) {
                _receiver = receiver;
                receiver.receiver_changed.connect (() => _sync_receiver ());
                receiver.sign_in_needed.connect ((url) => {
                    _spotify_sign_in_url = url;
                    if (_main_stack.visible_child_name == "spotify") _sign_in_spotify ();
                });
                if (_spotify_page != null) _spotify_page.set_receiver (receiver);
                _sync_receiver ();
                return;
            }
            if ((source.features & SourceFeatures.ISOLATED) != 0) {
                source.changed.connect (() => {
                    _update_spotify_row ();
                    if (_spotify_page != null) _spotify_page.set_web_source (_web_spotify ());
                });
                _update_spotify_row ();
                if (_spotify_page != null) _spotify_page.set_web_source (_web_spotify ());
                return;
            }
            _sync_source_row (source);
            source.changed.connect (() => {
                _sync_source_row (source);
                _browse.refresh_if_showing (source.id);
            });
            _update_welcome ();
        }

        private void _sync_source_row (MediaSource source) {
            if ((source.features & (SourceFeatures.BROWSE | SourceFeatures.SEARCH)) == 0) return;
            if (SourceAvailability.is_available (source)) _bin.add_source (source);
            else _bin.remove_source (source.id);
        }

        private void _on_source_removed (MediaSource source) {
            if (_receiver != null && (Object) source == (Object) _receiver) {
                _receiver = null;
                if (_pipe != null) _pipe.stop ();
                _pipe = null;
                if (_spotify_page != null) _spotify_page.set_receiver (null);
                return;
            }
            _bin.remove_source (source.id);
            if ((source.features & SourceFeatures.ISOLATED) != 0) {
                if (_spotify_page != null) _spotify_page.set_web_source (null);
                _update_spotify_row ();
            }
            if (_browse_source == source.id) {
                _browse_source = LocalSource.ID;
                _bin.select (LocalSource.ID, "songs");
                _browse.open_root (_local_source, "songs", _("Songs"));
                _main_stack.visible_child_name = "browse";
            }
        }

        private MediaSource? _web_spotify () {
            foreach (var s in _sources.sources) {
                if ((s.features & SourceFeatures.ISOLATED) == 0 || s is LocalReceiver || !(s is Browsable)) continue;
                if (SourceAvailability.is_available (s)) return s;
            }
            return null;
        }

        private void _update_spotify_row () {
            bool show = _setting ("show-spotify", true);
            if (show) _bin.add_service_row (SpotifyPage.ID, "audio-x-generic-symbolic", "Spotify");
            else _bin.remove_source (SpotifyPage.ID);
        }

        private bool _isolated_active () {
            return _isolated != null && _player == _isolated && _isolated_track != null;
        }

        private TrackInfo? _current () {
            if (_isolated_active ()) return _isolated_track;
            return _playlist.current_track;
        }

        private void _go_next () {
            if (_isolated_active ()) _isolated.remote.next.begin ();
            else _go_next ();
        }

        private void _go_prev () {
            if (_isolated_active ()) _isolated.remote.previous.begin ();
            else _go_prev ();
        }

        private void _play_isolated (RemotePlayer remote, MediaItem item, MediaItem? context) {
            _finish_scrobble ();
            if (_resolve_cancel != null) _resolve_cancel.cancel ();
            if (_isolated == null || _isolated.remote != remote) {
                _isolated = new RemoteBackend (remote);
                _connect_backend (_isolated);
                remote.state_changed.connect (() => _sync_isolated ());
            }
            _use_backend (_isolated);
            _isolated_track = TrackInfo.from_item (item);
            _isolated_track.resolved = true;
            _isolated.start (item, context);
            _refresh_track (_isolated_track);
            _load_cover (_isolated_track);
            _set_playing_ui (true);
            _lyrics.show_message (_("No lyrics for songs played on Spotify devices"));
            _update_actions ();
            var d = remote.device;
            if (d != null && d.name != "") _toast (_("Playing on %s").printf (d.name));
        }

        private void _sync_isolated () {
            if (!_isolated_active ()) return;
            var cur = _isolated.remote.current;
            if (cur == null || (_isolated_track.item != null && cur.key == _isolated_track.item.key)) return;
            _isolated_track = TrackInfo.from_item (cur);
            _isolated_track.resolved = true;
            _refresh_track (_isolated_track);
            _load_cover (_isolated_track);
        }

        private void _setup_actions () {
            var open = new SimpleAction ("open", null);
            open.activate.connect (() => _open_files ());
            add_action (open);
            var play_pause = new SimpleAction ("play-pause", null);
            play_pause.activate.connect (() => {
                if (_current () == null) return;
                _toggle_play ();
            });
            add_action (play_pause);
            var previous = new SimpleAction ("previous", null);
            previous.activate.connect (() => _go_prev ());
            add_action (previous);
            var next = new SimpleAction ("next", null);
            next.activate.connect (() => _go_next ());
            add_action (next);
            var stop = new SimpleAction ("stop", null);
            stop.activate.connect (() => {
                _player.pause ();
                _player.seek (0);
                _update_position (0, _player.get_duration ());
                _set_playing_ui (false);
            });
            add_action (stop);
            var skip_back = new SimpleAction ("skip-back", null);
            skip_back.activate.connect (() => _skip (-10));
            add_action (skip_back);
            var skip_forward = new SimpleAction ("skip-forward", null);
            skip_forward.activate.connect (() => _skip (10));
            add_action (skip_forward);
            var share = Singularity.Share.add_action (this, this, () => {
                var track = _playlist.current_track;
                if (track == null) return null;
                if (track.uri.has_prefix ("file://")) return new Singularity.ShareContent.for_files ({ File.new_for_uri (track.uri) });
                if (track.external_url != "") return new Singularity.ShareContent.for_uris ({ track.external_url }, track.title);
                if (track.uri == "") return null;
                return new Singularity.ShareContent.for_uris ({ track.uri }, track.title);
            });
            share.bind_property ("enabled", _share_btn, "visible", BindingFlags.SYNC_CREATE);
            _track_actions = { play_pause, previous, next, stop, skip_back, skip_forward, share };
            var shuffle = new SimpleAction.stateful ("shuffle", null, new Variant.boolean (_playlist.shuffle));
            shuffle.activate.connect (() => _toggle_shuffle ());
            add_action (shuffle);
            _shuffle_action = shuffle;
            var repeat = new SimpleAction.stateful ("repeat", VariantType.STRING, new Variant.string ("none"));
            repeat.activate.connect ((param) => {
                string mode = param.get_string ();
                _set_repeat (mode == "all" ? 1 : (mode == "one" ? 2 : 0));
            });
            add_action (repeat);
            _repeat_action = repeat;
            var vol_up = new SimpleAction ("volume-up", null);
            vol_up.activate.connect (() => _now_playing.volume = _now_playing.volume + 0.1);
            add_action (vol_up);
            var vol_down = new SimpleAction ("volume-down", null);
            vol_down.activate.connect (() => _now_playing.volume = _now_playing.volume - 0.1);
            add_action (vol_down);
            var mute = new SimpleAction.stateful ("mute", null, new Variant.boolean (false));
            mute.activate.connect (() => {
                bool muted = !mute.get_state ().get_boolean ();
                _player.set_muted (muted);
                mute.set_state (new Variant.boolean (muted));
            });
            add_action (mute);
            var clear = new SimpleAction ("clear-playlist", null);
            clear.activate.connect (() => _playlist.clear ());
            add_action (clear);
            var show_playlist = new SimpleAction ("playlist", null);
            show_playlist.activate.connect (() => _show_playlist_popover (null));
            add_action (show_playlist);
            var mini = new SimpleAction ("mini-player", null);
            mini.activate.connect (() => _toggle_mini_player ());
            add_action (mini);
            var close_action = new SimpleAction ("close", null);
            close_action.activate.connect (() => close ());
            add_action (close_action);
            var library = new SimpleAction ("library", null);
            library.activate.connect (() => _show_browse ());
            add_action (library);
            var now = new SimpleAction ("now-playing", null);
            now.activate.connect (() => _show_player ());
            add_action (now);
            var find = new SimpleAction ("find", null);
            find.activate.connect (() => {
                _show_browse ();
                set_sidebar_visible (true);
                _bin.focus_search ();
            });
            add_action (find);
            var lyrics = new SimpleAction ("lyrics", null);
            lyrics.activate.connect (() => _toggle_lyrics ());
            add_action (lyrics);
            _list_actions = { clear, show_playlist, mini, now };
            _update_actions ();
            _playlist.current_changed.connect (() => _update_actions ());
            _playlist.track_added.connect (() => _update_actions ());
            _playlist.cleared.connect (() => _update_actions ());
        }

        private SimpleAction[] _track_actions = {};
        private SimpleAction[] _list_actions = {};
        private SimpleAction _shuffle_action;
        private SimpleAction _repeat_action;

        private void _update_actions () {
            bool has_track = _current () != null;
            foreach (var a in _track_actions) a.set_enabled (has_track);
            bool has_list = _playlist.count > 0;
            foreach (var a in _list_actions) a.set_enabled (has_list);
            _bin.show_now_playing (has_list || _isolated_active ());
            _transport.queue_btn.sensitive = has_list;
        }

        private void _skip (int seconds) {
            int64 dur = _player.get_duration ();
            int64 pos = _player.get_position () + (int64) seconds * 1000000000;
            if (pos < 0) pos = 0;
            if (dur > 0 && pos > dur) pos = dur;
            _player.seek (pos);
        }

        private void _set_repeat (int mode) {
            _repeat_mode = mode;
            _playlist.repeat_all = (_repeat_mode == 1);
            _playlist.repeat_one = (_repeat_mode == 2);
            _now_playing.set_repeat_state (_repeat_mode);
            _transport.repeat_btn.active = _repeat_mode != 0;
            _transport.repeat_btn.icon_name = _repeat_mode == 2 ? "media-playlist-repeat-song-symbolic" : "media-playlist-repeat-symbolic";
            _repeat_action.set_state (new Variant.string (_repeat_mode == 1 ? "all" : (_repeat_mode == 2 ? "one" : "none")));
        }

        private void _build_ui () {
            _bin = new MediaBin ();
            _bin.navigate.connect ((source_id, node, title) => _navigate (source_id, node, title));
            _bin.now_playing_selected.connect (() => _show_player ());
            _bin.open_files.connect (() => _open_files ());
            _bin.search_changed.connect ((text) => _on_search (text));
            set_sidebar (_bin);
            set_sidebar_visible (true);

            _root_stack = new Stack ();
            _root_stack.transition_type = StackTransitionType.CROSSFADE;
            _root_stack.transition_duration = 200;
            _root_stack.hexpand = true;
            _root_stack.vexpand = true;

            var browse_box = new Box (Orientation.VERTICAL, 0);
            _main_stack = new Stack ();
            _main_stack.vexpand = true;
            _main_stack.transition_type = StackTransitionType.CROSSFADE;
            _main_stack.transition_duration = 150;
            _browse = new BrowsePage ();
            _browse.play_items.connect ((items, start, shuffle) => _play_items (items, start, shuffle));
            _browse.enqueue_items.connect ((items, next) => _enqueue (items, next));
            _browse.open_uri.connect ((uri) => _open_uri (uri));
            _main_stack.add_named (_browse, "browse");

            _welcome = new Singularity.Widgets.WelcomePage ();
            _welcome.app_icon_name = "dev.sinty.music";
            _welcome.title = _("Music");
            _welcome.subtitle = _("Play your music collection");
            _welcome.add_action ("folder-open", _("Open Files"), _("Add audio files or entire folders to the queue."), () => _open_files ());
            _welcome.add_action ("folder-music", _("Choose Music Folder"), _("Show the songs of a folder in the library."), () => _choose_folder ());
            _welcome.add_action ("network-server", _("Add a Music Service"), _("Connect Jellyfin, Navidrome or ListenBrainz in Online Accounts."), () => _open_uri ("settings:accounts"));
            _main_stack.add_named (_welcome, "welcome");
            browse_box.append (_main_stack);

            _transport = new TransportStrip ();
            _transport.play_pause_clicked.connect (() => _toggle_play ());
            _transport.prev_clicked.connect (() => _go_prev ());
            _transport.next_clicked.connect (() => _go_next ());
            _transport.seek_requested.connect ((frac) => {
                int64 dur = _player.get_duration ();
                if (dur > 0) _player.seek ((int64) (frac * dur));
            });
            _transport.open_player.connect (() => {
                if (_current () != null) _show_player ();
            });
            _transport.shuffle_btn.toggled.connect (() => {
                if (_transport.shuffle_btn.active != _playlist.shuffle) _toggle_shuffle ();
            });
            _transport.repeat_btn.clicked.connect (() => _cycle_repeat ());
            _transport.queue_btn.clicked.connect (() => _show_playlist_popover (_transport.queue_btn));
            browse_box.append (_transport);
            _root_stack.add_named (browse_box, "browse");

            _now_playing = new NowPlayingPage ();
            _now_playing.play_pause_clicked.connect (() => _toggle_play ());
            _now_playing.prev_clicked.connect (() => _go_prev ());
            _now_playing.next_clicked.connect (() => _go_next ());
            _now_playing.shuffle_clicked.connect (_toggle_shuffle);
            _now_playing.repeat_clicked.connect (_cycle_repeat);
            _now_playing.seek_requested.connect ((frac) => {
                int64 dur = _player.get_duration ();
                if (dur > 0) _player.seek ((int64)(frac * dur));
            });
            _now_playing.volume_changed.connect ((v) => {
                if (_isolated_active () && _pipe != null) _pipe.set_volume (v);
                else _player.set_volume (v);
            });
            _now_playing.playlist_btn.clicked.connect (() => _show_playlist_popover (_now_playing.playlist_btn));

            _lyrics = new LyricsView ();
            _lyrics_revealer = new Revealer ();
            _lyrics_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
            _lyrics_revealer.set_child (_lyrics);
            _lyrics_revealer.reveal_child = false;
            var player_row = new Box (Orientation.HORIZONTAL, 0);
            player_row.append (_now_playing);
            player_row.append (_lyrics_revealer);
            _root_stack.add_named (player_row, "player");

            _back_btn = add_bubble_icon ("go-previous-symbolic", _("Library (Ctrl+1)"), () => _show_browse ());
            _lyrics_btn = add_bubble_icon ("format-justify-left-symbolic", _("Lyrics (Ctrl+Y)"), () => _toggle_lyrics ());
            _mini_btn = add_bubble_icon ("go-down-symbolic", _("Mini Player"), () => _toggle_mini_player ());
            _share_btn = add_bubble_icon ("singularity-share-symbolic", _("Share"), () => ((GLib.ActionGroup) this).activate_action ("share", null));

            _root_stack.visible_child_name = "browse";
            _root_stack.notify["visible-child-name"].connect (() => _sync_chrome ());
            set_content (_root_stack);
            _sync_chrome ();
        }

        private void _sync_chrome () {
            bool player = _root_stack.visible_child_name == "player";
            _back_btn.visible = player;
            _lyrics_btn.visible = player;
            _mini_btn.visible = player;
            show_close = !player;
        }

        private void _show_browse () {
            _root_stack.visible_child_name = "browse";
            if (_browse_source == "now") _browse_source = LocalSource.ID;
        }

        private void _show_player () {
            if (_current () == null) return;
            _root_stack.visible_child_name = "player";
            _bin.set_active ("now");
        }

        private void _update_welcome () {
            bool others = false;
            foreach (var s in _sources.sources) {
                if (s.id != LocalSource.ID && _bin.has_source (s.id)) others = true;
            }
            bool empty = _local_source.library.all.size == 0 && !others && _playlist.count == 0;
            if (_main_stack.visible_child_name == "spotify") return;
            _main_stack.visible_child_name = empty && _browse_source == LocalSource.ID ? "welcome" : "browse";
        }

        private void _navigate (string source_id, string? node, string title) {
            _root_stack.visible_child_name = "browse";
            if (source_id == SpotifyPage.ID) {
                _browse_source = source_id;
                _ensure_spotify_page ();
                _main_stack.visible_child_name = "spotify";
                _sign_in_spotify ();
                return;
            }
            var source = _sources.find (source_id);
            if (source == null) return;
            _browse_source = source_id;
            _browse.open_root (source, node, title);
            _main_stack.visible_child_name = "browse";
            _update_welcome ();
        }

        private void _ensure_spotify_page () {
            if (_spotify_page != null) return;
            _spotify_page = new SpotifyPage (_spotify, _host);
            _spotify_page.open_uri.connect ((uri) => _open_uri (uri));
            _spotify_page.play_remote.connect ((remote, item, context) => _play_isolated (remote, item, context));
            _spotify_page.set_web_source (_web_spotify ());
            _spotify_page.set_receiver (_receiver);
            _main_stack.add_named (_spotify_page, "spotify");
        }

        private void _on_search (string text) {
            if (_search_timer != 0) Source.remove (_search_timer);
            _search_timer = Timeout.add (300, () => {
                _search_timer = 0;
                _root_stack.visible_child_name = "browse";
                if (_browse_source == SpotifyPage.ID) {
                    if (_spotify_page != null) _spotify_page.search (text.strip ());
                    return Source.REMOVE;
                }
                var source = _sources.find (_browse_source) ?? _local_source;
                if (text.strip () == "") {
                    _browse.close_search ();
                } else if (source is Searchable) {
                    _main_stack.visible_child_name = "browse";
                    _browse.open_search (source, text.strip ());
                }
                return Source.REMOVE;
            });
        }

        private void _open_uri (string uri) {
            if (uri == "music:open-files") {
                _open_files ();
                return;
            }
            if (uri == "settings:accounts" || uri == "settings:app") {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    if (uri == "settings:app") shell.open_app_settings ("dev.sinty.music");
                    else shell.open_settings ("accounts");
                } catch (Error e) {
                    warning ("music: %s", e.message);
                }
                return;
            }
            _host.open_external (uri);
        }

        private void _show_playlist_popover (Widget? anchor) {
            Widget target = _transport.queue_btn;
            if (anchor != null) target = anchor;
            else if (_root_stack.visible_child_name == "player") target = _now_playing.playlist_btn;
            if (_playlist_popover == null) {
                var box = new Box (Orientation.VERTICAL, 0);
                box.set_size_request (320, -1);

                var header = new Box (Orientation.HORIZONTAL, 0);
                header.margin_start  = 12;
                header.margin_end    = 4;
                header.margin_top    = 8;
                header.margin_bottom = 4;

                var lbl = new Label (_("Queue"));
                lbl.add_css_class ("heading");
                lbl.halign  = Align.START;
                lbl.hexpand = true;
                header.append (lbl);

                var add_btn = new Button.from_icon_name ("list-add-symbolic");
                add_btn.add_css_class ("flat");
                add_btn.tooltip_text = _("Add Files");
                add_btn.clicked.connect (() => {
                    _playlist_popover.popdown ();
                    _open_files ();
                });
                header.append (add_btn);

                var clear_btn = new Button.from_icon_name ("edit-clear-all-symbolic");
                clear_btn.add_css_class ("flat");
                clear_btn.tooltip_text = _("Clear Queue");
                clear_btn.clicked.connect (() => {
                    _playlist_popover.popdown ();
                    _playlist.clear ();
                });
                header.append (clear_btn);
                box.append (header);

                var sep = new Separator (Orientation.HORIZONTAL);
                sep.margin_bottom = 4;
                box.append (sep);

                var scroll = new ScrolledWindow ();
                scroll.vexpand = true;
                scroll.hscrollbar_policy = PolicyType.NEVER;
                scroll.set_size_request (-1, 320);

                _playlist_box = new ListBox ();
                _playlist_box.selection_mode = SelectionMode.SINGLE;
                _playlist_box.row_activated.connect ((row) => {
                    _playlist_popover.popdown ();
                    _play_track (_playlist.play_index (row.get_index ()));
                });
                for (int i = 0; i < _playlist.count; i++) {
                    var t = _playlist.get_track (i);
                    if (t != null) _add_playlist_row (t, -1);
                }
                _select_current_row ();

                scroll.set_child (_playlist_box);
                box.append (scroll);

                _playlist_popover = new Popover ();
                _playlist_popover.set_child (box);
                _playlist_popover.has_arrow = true;
            }
            if (_playlist_popover.get_parent () != target) {
                if (_playlist_popover.get_parent () != null) _playlist_popover.unparent ();
                _playlist_popover.set_parent (target);
            }
            _playlist_popover.popup ();
        }

        private void _select_current_row () {
            if (_playlist_box == null || _playlist.current_index < 0) return;
            var row = _playlist_box.get_row_at_index (_playlist.current_index);
            if (row != null) _playlist_box.select_row (row);
        }

        private void _connect_backend (PlayerBackend backend) {
            backend.position_updated.connect ((pos, dur) => {
                if (backend != _player) return;
                _update_position (pos, dur);
            });
            backend.track_ended.connect (() => {
                if (backend != _player) return;
                _finish_scrobble ();
                var next = _playlist.next ();
                if (next != null) {
                    _play_track (next);
                } else {
                    _set_playing_ui (false);
                    _mpris.set_stopped ();
                }
            });
            backend.playing_changed.connect ((playing) => {
                if (backend != _player) return;
                _set_playing_ui (playing);
            });
            backend.metadata_ready.connect ((title, artist, album, dur, cover) => {
                if (backend != _player || backend == _isolated) return;
                var t = _playlist.current_track;
                if (t == null) return;
                if (title  != null && t.source_id == "") t.title  = title;
                if (artist != null && t.source_id == "") t.artist = artist;
                if (album  != null && t.source_id == "") t.album  = album;
                if (dur > 0) t.duration = dur;
                if (cover  != null) t.cover  = cover;
                _refresh_track (t);
            });
            backend.error_occurred.connect ((msg) => {
                if (backend != _player) return;
                warning ("music: %s", msg);
                var t = _current ();
                if (t != null && t.source_id != "") _toast (_("Could not play %s: %s").printf (t.title, msg));
            });
        }

        private void _update_position (int64 pos, int64 dur) {
            _now_playing.update_position (pos, dur);
            _transport.update_position (pos, dur);
            _mpris.update_position (pos);
            if (_mini != null) _mini.update_position (pos, dur);
            _lyrics.update_position (pos);
            if (_scrobble_track != null && _player.is_playing) {
                if (_scrobble_last >= 0 && pos > _scrobble_last && pos - _scrobble_last < 2000000000) _scrobble_played += pos - _scrobble_last;
                _scrobble_last = pos;
            }
        }

        private void _set_playing_ui (bool playing) {
            _now_playing.set_playing (playing);
            _transport.set_playing (playing);
            _mpris.update_playback (playing);
            if (_mini != null) _mini.update_playback (playing);
        }

        private void _refresh_track (TrackInfo t) {
            _now_playing.update_track (t);
            _transport.update_track (t);
            _mpris.update_track (t, t.cover != null ? (t.cover as Gdk.Texture) : null);
            if (_mini != null) _mini.update_track (t);
        }

        private void _connect_signals () {
            _connect_backend (_local);

            _playlist.track_added.connect ((track) => _add_playlist_row (track, -1));
            _playlist.track_inserted.connect ((index, track) => _add_playlist_row (track, index));

            _playlist.track_removed.connect ((index) => {
                if (_playlist_box == null) return;
                var row = _playlist_box.get_row_at_index (index);
                if (row != null) _playlist_box.remove (row);
                _renumber_playlist ();
            });

            _playlist.cleared.connect (() => {
                _finish_scrobble ();
                if (_playlist_box != null) {
                    Widget? c = _playlist_box.get_first_child ();
                    while (c != null) {
                        var next = c.get_next_sibling ();
                        _playlist_box.remove (c);
                        c = next;
                    }
                }
                _player.stop ();
                _use_backend (_local);
                _root_stack.visible_child_name = "browse";
                _now_playing.update_track (null);
                _transport.update_track (null);
                _set_playing_ui (false);
                _now_playing.reset_position ();
                _mpris.set_stopped ();
                _mpris.update_track (null, null);
                if (_mini != null) {
                    _mini.update_track (null);
                    _mini.update_playback (false);
                    _mini.reset_position ();
                }
                _update_welcome ();
            });

            _playlist.current_changed.connect ((track) => {
                if (track != null) _now_playing.update_track (track);
                _select_current_row ();
            });
        }

        private void _add_playlist_row (TrackInfo track, int index) {
            if (_playlist_box == null) return;
            var row  = new ListBoxRow ();
            var hbox = new Box (Orientation.HORIZONTAL, 8);
            hbox.margin_start  = 12;
            hbox.margin_end    = 12;
            hbox.margin_top    = 6;
            hbox.margin_bottom = 6;

            var num = new Label (null);
            num.add_css_class ("dim-label");
            num.add_css_class ("numeric");
            num.width_chars = 2;
            num.xalign = 1.0f;

            var info = new Box (Orientation.VERTICAL, 1);
            info.hexpand = true;

            var tl = new Label (track.title);
            tl.halign    = Align.START;
            tl.ellipsize = Pango.EllipsizeMode.END;

            var al = new Label (track.artist != _("Unknown Artist") && track.artist != "Unknown Artist" ? track.artist : "");
            al.halign = Align.START;
            al.add_css_class ("dim-label");
            al.add_css_class ("caption");
            al.ellipsize = Pango.EllipsizeMode.END;

            info.append (tl);
            info.append (al);
            hbox.append (num);
            hbox.append (info);
            row.set_child (hbox);
            if (index < 0) _playlist_box.append (row);
            else _playlist_box.insert (row, index);
            _renumber_playlist ();
        }

        private void _renumber_playlist () {
            if (_playlist_box == null) return;
            for (var row = _playlist_box.get_first_child (); row != null; row = row.get_next_sibling ()) {
                var lr = row as ListBoxRow;
                var num = lr?.get_child ()?.get_first_child () as Label;
                if (num != null) num.label = "%d".printf (lr.get_index () + 1);
            }
        }

        private void _use_backend (PlayerBackend backend) {
            if (_player == backend) return;
            if (_player == _remote && _remote != null) _remote.detach ();
            if (_player == _isolated && _isolated != null) {
                if (_isolated.is_playing) _isolated.pause ();
                _isolated.detach ();
            }
            if (_player == _local) _local.stop ();
            _player = backend;
            _transport.set_seekable (backend.can_seek);
        }

        private void _toggle_play () {
            if (_current () == null) return;
            _player.toggle_play_pause ();
        }

        private void _play_items (Gee.List<MediaItem> items, int start, bool shuffle) {
            if (items.size == 0) return;
            _finish_scrobble ();
            _player.pause ();
            _playlist.clear ();
            foreach (var it in items) _playlist.add_track (TrackInfo.from_item (it));
            if (shuffle != _playlist.shuffle) _toggle_shuffle ();
            _play_track (_playlist.play_index (start.clamp (0, items.size - 1)));
            _update_welcome ();
        }

        private void _enqueue (Gee.List<MediaItem> items, bool next) {
            bool was_empty = _playlist.count == 0;
            foreach (var it in items) {
                var t = TrackInfo.from_item (it);
                if (next) _playlist.insert_next (t);
                else _playlist.add_track (t);
            }
            _toast (ngettext ("Added %d song to the queue", "Added %d songs to the queue", items.size).printf (items.size));
            if (was_empty) _play_track (_playlist.play_index (0));
        }

        private void _play_track (TrackInfo? track) {
            if (track == null) return;
            _finish_scrobble ();
            if (_resolve_cancel != null) _resolve_cancel.cancel ();
            _resolve_cancel = new Cancellable ();
            _refresh_track (track);
            _load_cover (track);
            if (!track.resolved && track.item != null) {
                _resolve_and_play.begin (track, _resolve_cancel);
                return;
            }
            _use_backend (_local);
            _local.set_headers (null);
            _start_local (track);
        }

        private void _start_local (TrackInfo track) {
            _local.load_uri (track.uri);
            _local.play ();
            _after_start (track);
        }

        private void _after_start (TrackInfo track) {
            _set_playing_ui (true);
            _select_current_row ();
            if (_mini != null) {
                _mini.update_track (track);
                _mini.update_playback (true);
            }
            _begin_scrobble (track);
            _load_lyrics (track);
            _update_actions ();
        }

        private async void _resolve_and_play (TrackInfo track, Cancellable cancel) {
            var source = _sources.find (track.source_id);
            var resolver = source as PlaybackResolver;
            if (resolver == null) {
                _toast (_("%s is no longer available").printf (track.source_id));
                return;
            }
            try {
                var pb = yield resolver.resolve (track.item, cancel);
                if (cancel.is_cancelled () || _playlist.current_track != track) return;
                switch (pb.kind) {
                    case PlaybackKind.STREAM: {
                        track.uri = pb.uri;
                        track.resolved = true;
                        var headers = new HashTable<string, string> (str_hash, str_equal);
                        foreach (var name in pb.get_header_names ()) headers.insert (name, pb.get_header (name));
                        _use_backend (_local);
                        _local.set_headers (headers.size () > 0 ? headers : null);
                        _start_local (track);
                        if (pb.start_ms > 0) _local.seek (pb.start_ms * 1000000);
                        break;
                    }
                    case PlaybackKind.REMOTE: {
                        if (_remote == null || _remote.remote != pb.remote) {
                            _remote = new RemoteBackend (pb.remote);
                            _connect_backend (_remote);
                        }
                        _use_backend (_remote);
                        _remote.start (track.item, null);
                        _after_start (track);
                        break;
                    }
                    default: {
                        string url = pb.uri != "" ? pb.uri : track.external_url;
                        if (url != "") _open_uri (url);
                        _toast (_("%s opens in its own app").printf (track.title));
                        break;
                    }
                }
            } catch (IOError.CANCELLED e) {
            } catch (Error e) {
                _toast (_("Could not play %s: %s").printf (track.title, e.message));
                _set_playing_ui (false);
            }
        }

        private void _load_cover (TrackInfo track) {
            if (track.cover != null) return;
            if (track.image_url == "") {
                if (_setting ("online-artwork", true) && track != _isolated_track) _enrich.begin (track);
                return;
            }
            Artwork.get_default ().load.begin (track.image_url, null, (o, r) => {
                var tex = Artwork.get_default ().load.end (r);
                if (tex == null || track.cover != null) return;
                track.cover = tex;
                if (_current () == track) _refresh_track (track);
            });
        }

        private async void _enrich (TrackInfo track) {
            var item = track.to_item ();
            foreach (var mp in _sources.metadata_providers ()) {
                try {
                    var better = yield mp.enrich (item, null);
                    if (better == null) continue;
                    if (better.image_url != "" && track.image_url == "") {
                        track.image_url = better.image_url;
                        if (track.item != null && track.item.image_url == "") track.item.image_url = better.image_url;
                        _load_cover (track);
                    }
                    if (track.album == _("Unknown Album") && better.album != "") track.album = better.album;
                    return;
                } catch (Error e) {
                    debug ("music: details: %s", e.message);
                }
            }
        }

        private void _begin_scrobble (TrackInfo track) {
            _scrobble_track = track;
            _scrobble_started = new DateTime.now_utc ();
            _scrobble_played = 0;
            _scrobble_last = -1;
            if (!_setting ("scrobble", true)) return;
            var item = track.to_item ();
            foreach (var sc in _sources.scrobblers ()) {
                if (!sc.enabled) continue;
                sc.now_playing.begin (item, null, (o, r) => {
                    try {
                        sc.now_playing.end (r);
                    } catch (Error e) {
                        debug ("music: now playing: %s", e.message);
                    }
                });
            }
        }

        private void _finish_scrobble () {
            var track = _scrobble_track;
            _scrobble_track = null;
            if (track == null || _scrobble_started == null) return;
            if (!_setting ("scrobble", true)) return;
            int64 played_ms = _scrobble_played / 1000000;
            if (!Scrobbler.counts_as_listen (track.duration / 1000000, played_ms)) return;
            var item = track.to_item ();
            var started = _scrobble_started;
            foreach (var sc in _sources.scrobblers ()) {
                if (!sc.enabled) continue;
                sc.listened.begin (item, played_ms, started, null, (o, r) => {
                    try {
                        sc.listened.end (r);
                    } catch (Error e) {
                        debug ("music: listen: %s", e.message);
                    }
                });
            }
        }

        private void _load_lyrics (TrackInfo track) {
            if (_lyrics_cancel != null) _lyrics_cancel.cancel ();
            _lyrics_cancel = new Cancellable ();
            _lyrics.show_message (_("Looking for lyrics…"));
            _find_lyrics.begin (track, _lyrics_cancel);
        }

        private async void _find_lyrics (TrackInfo track, Cancellable cancel) {
            var item = track.to_item ();
            foreach (var mp in _sources.metadata_providers ()) {
                var source = mp as MediaSource;
                if (source != null && (source.features & SourceFeatures.LYRICS) == 0) continue;
                if (!_setting ("online-lyrics", true) && source != null && source.id != track.source_id) continue;
                try {
                    var l = yield mp.lyrics (item, cancel);
                    if (cancel.is_cancelled ()) return;
                    if (l != null) {
                        _lyrics.set_lyrics (l);
                        return;
                    }
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (Error e) {
                    debug ("music: lyrics: %s", e.message);
                }
            }
            if (!cancel.is_cancelled ()) _lyrics.show_message (_("No lyrics for this song"));
        }

        private void _toggle_lyrics () {
            _lyrics_revealer.reveal_child = !_lyrics_revealer.reveal_child;
            if (_lyrics_revealer.reveal_child) _lyrics_btn.add_css_class ("accent");
            else _lyrics_btn.remove_css_class ("accent");
        }

        private void _toggle_shuffle () {
            _playlist.shuffle = !_playlist.shuffle;
            _now_playing.set_shuffle_active (_playlist.shuffle);
            if (_transport.shuffle_btn.active != _playlist.shuffle) _transport.shuffle_btn.active = _playlist.shuffle;
            _shuffle_action.set_state (new Variant.boolean (_playlist.shuffle));
        }

        private void _cycle_repeat () {
            _set_repeat ((_repeat_mode + 1) % 3);
        }

        private void _toggle_mini_player () {
            if (_mini_mode) {
                if (_mini != null) _mini.hide ();
                present ();
                _mini_mode = false;
            } else {
                if (_mini == null) {
                    _mini = new MiniPlayer (application);
                    _mini.play_pause_clicked.connect (() => _toggle_play ());
                    _mini.prev_clicked.connect (() => _go_prev ());
                    _mini.next_clicked.connect (() => _go_next ());
                    _mini.seek_requested.connect ((frac) => {
                        int64 dur = _player.get_duration ();
                        if (dur > 0) _player.seek ((int64)(frac * dur));
                    });
                    _mini.expand_clicked.connect (() => {
                        _mini_mode = false;
                        _mini.hide ();
                        present ();
                    });
                    _mini.update_track (_current ());
                    _mini.update_playback (_player.is_playing);
                }
                _mini.present ();
                hide ();
                _mini_mode = true;
            }
        }

        private void _open_files () {
            var dialog = new FileDialog ();
            dialog.title = _("Open Audio Files");
            var filters      = new GLib.ListStore (typeof (FileFilter));
            var audio_filter = new FileFilter ();
            audio_filter.name = _("Audio Files");
            audio_filter.add_mime_type ("audio/*");
            filters.append (audio_filter);
            dialog.filters = filters;
            dialog.open_multiple.begin (this, null, (obj, res) => {
                try {
                    var files = dialog.open_multiple.end (res);
                    string[] uris = {};
                    for (int i = 0; i < (int) files.get_n_items (); i++) {
                        var f = files.get_item (i) as File;
                        if (f != null) uris += f.get_uri ();
                    }
                    open_uris (uris);
                } catch {}
            });
        }

        private void _choose_folder () {
            var dialog = new FileDialog ();
            dialog.title = _("Choose Music Folder");
            dialog.select_folder.begin (this, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    if (folder == null || folder.get_path () == null) return;
                    if (_settings != null) _settings.set_string ("library-folder", folder.get_path ());
                    else {
                        _local_source.library.folder = folder.get_path ();
                        _local_source.library.invalidate ();
                    }
                    _main_stack.visible_child_name = "browse";
                    _browse.reload ();
                } catch {}
            });
        }

        public void open_uris (string[] uris) {
            bool start = _playlist.current_index < 0;
            int first = _playlist.count;
            _playlist.add_uris (uris);
            if (start && _playlist.count > first) _play_track (_playlist.play_index (first));
            _update_welcome ();
        }

        public void play_uris (string[] uris) {
            if (uris.length == 0) return;
            _player.pause ();
            _playlist.clear ();
            _playlist.add_uris (uris);
            _play_track (_playlist.play_index (0));
            _update_welcome ();
        }
    }
}
