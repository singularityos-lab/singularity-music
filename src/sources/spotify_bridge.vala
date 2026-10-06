namespace Singularity.Apps.Music {

    public class SpotifyBridge : Object {
        public const string BUS_NAME = "org.mpris.MediaPlayer2.spotify";
        private const string[] DESKTOP_IDS = { "spotify.desktop", "com.spotify.Client.desktop", "spotify_spotify.desktop", "spotify-client.desktop" };

        private DBusProxy? _player = null;
        private DBusProxy? _root = null;
        private uint _watch = 0;
        private uint _poll = 0;
        private bool _polling = false;

        public bool running { get; private set; default = false; }
        public bool installed { get; private set; default = false; }
        public bool playing { get; private set; default = false; }
        public string title { get; private set; default = ""; }
        public string artist { get; private set; default = ""; }
        public string album { get; private set; default = ""; }
        public string art_url { get; private set; default = ""; }
        public string track_url { get; private set; default = ""; }
        public int64 length_us { get; private set; default = 0; }
        public int64 position_us { get; private set; default = 0; }
        public bool can_control { get; private set; default = false; }

        public signal void changed ();
        public signal void position_changed ();

        public SpotifyBridge () {
            installed = app_info () != null;
            _watch = Bus.watch_name (BusType.SESSION, BUS_NAME, BusNameWatcherFlags.NONE,
                (conn, name, owner) => connect_player.begin (),
                (conn, name) => {
                    _player = null;
                    _root = null;
                    running = false;
                    playing = false;
                    title = "";
                    artist = "";
                    album = "";
                    art_url = "";
                    changed ();
                });
        }

        public static AppInfo? app_info () {
            foreach (unowned string id in DESKTOP_IDS) {
                var info = new DesktopAppInfo (id);
                if (info != null) return info;
            }
            return null;
        }

        private async void connect_player () {
            try {
                _player = yield new DBusProxy.for_bus (BusType.SESSION, DBusProxyFlags.GET_INVALIDATED_PROPERTIES, null,
                    BUS_NAME, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", null);
                _root = yield new DBusProxy.for_bus (BusType.SESSION, DBusProxyFlags.NONE, null,
                    BUS_NAME, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", null);
                _player.g_properties_changed.connect (() => read ());
                _player.g_signal.connect ((sender, name, args) => {
                    if (name == "Seeked") {
                        position_us = args.get_child_value (0).get_int64 ();
                        position_changed ();
                    }
                });
                running = true;
                installed = true;
                read ();
                refresh_position.begin ();
            } catch (Error e) {
                warning ("music: spotify bridge: %s", e.message);
            }
        }

        private static string str (Variant? v) {
            if (v == null) return "";
            if (v.is_of_type (VariantType.STRING)) return v.get_string ();
            if (v.is_of_type (VariantType.OBJECT_PATH)) return v.get_string ();
            if (v.is_of_type (VariantType.STRING_ARRAY)) return string.joinv (", ", v.get_strv ());
            return "";
        }

        private void read () {
            if (_player == null) return;
            var status = _player.get_cached_property ("PlaybackStatus");
            playing = status != null && status.get_string () == "Playing";
            var cc = _player.get_cached_property ("CanControl");
            can_control = cc == null || cc.get_boolean ();
            var meta = _player.get_cached_property ("Metadata");
            if (meta != null && meta.is_of_type (new VariantType ("a{sv}"))) {
                var dict = new VariantDict (meta);
                title = str (dict.lookup_value ("xesam:title", null));
                artist = str (dict.lookup_value ("xesam:artist", null));
                album = str (dict.lookup_value ("xesam:album", null));
                art_url = str (dict.lookup_value ("mpris:artUrl", null));
                track_url = str (dict.lookup_value ("xesam:url", null));
                var len = dict.lookup_value ("mpris:length", null);
                length_us = len == null ? 0 : (len.is_of_type (VariantType.INT64) ? len.get_int64 () : (len.is_of_type (VariantType.UINT64) ? (int64) len.get_uint64 () : 0));
            }
            changed ();
        }

        public void set_polling (bool on) {
            if (on && _poll == 0) {
                _poll = Timeout.add (1000, () => {
                    refresh_position.begin ();
                    return Source.CONTINUE;
                });
            } else if (!on && _poll != 0) {
                Source.remove (_poll);
                _poll = 0;
            }
        }

        private async void refresh_position () {
            if (_player == null || _polling) return;
            _polling = true;
            try {
                var reply = yield _player.get_connection ().call (BUS_NAME, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "Get",
                    new Variant ("(ss)", "org.mpris.MediaPlayer2.Player", "Position"), new VariantType ("(v)"), DBusCallFlags.NONE, 2000, null);
                Variant v;
                reply.get ("(v)", out v);
                position_us = v.is_of_type (VariantType.INT64) ? v.get_int64 () : 0;
                position_changed ();
            } catch (Error e) {
            }
            _polling = false;
        }

        private void call (string method, Variant? args = null) {
            if (_player == null) return;
            _player.call.begin (method, args, DBusCallFlags.NONE, 3000, null, (o, r) => {
                try {
                    _player.call.end (r);
                } catch (Error e) {
                    warning ("music: spotify %s: %s", method, e.message);
                }
                refresh_position.begin ();
            });
        }

        public void play_pause () {
            call ("PlayPause");
        }

        public void next () {
            call ("Next");
        }

        public void previous () {
            call ("Previous");
        }

        public void seek_to (int64 position_us) {
            var meta = _player != null ? _player.get_cached_property ("Metadata") : null;
            string track = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
            if (meta != null) {
                var id = new VariantDict (meta).lookup_value ("mpris:trackid", null);
                if (id != null) track = id.get_string ();
            }
            if (Variant.is_object_path (track)) call ("SetPosition", new Variant ("(ox)", track, position_us));
        }

        public void raise_or_launch (Gtk.Window? parent) {
            if (_root != null) {
                _root.call.begin ("Raise", null, DBusCallFlags.NONE, 3000, null, (o, r) => {
                    try {
                        _root.call.end (r);
                    } catch (Error e) {
                        launch (parent);
                    }
                });
                return;
            }
            launch (parent);
        }

        private void launch (Gtk.Window? parent) {
            var info = app_info ();
            if (info == null) return;
            try {
                info.launch (null, parent != null ? parent.get_display ().get_app_launch_context () : null);
            } catch (Error e) {
                warning ("music: %s", e.message);
            }
        }
    }
}
