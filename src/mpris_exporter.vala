using GLib;
using Gdk;

namespace Singularity.Apps.Music {

    [DBus (name = "org.mpris.MediaPlayer2")]
    public class MprisRoot : Object {
        public bool   can_quit           { get { return true;  } }
        public bool   can_raise          { get { return false; } }
        public bool   has_track_list     { get { return false; } }
        public string identity           { get { return "Singularity Music"; } }
        public string desktop_entry      { get { return "dev.sinty.music"; } }
        public string[] supported_uri_schemes {
            owned get { return {"file"}; }
        }
        public string[] supported_mime_types  {
            owned get { return {"audio/mpeg", "audio/ogg", "audio/flac", "audio/x-wav", "audio/mp4"}; }
        }
        public void raise () {}
        public void quit ()  { GLib.Application.get_default ()?.quit (); }
    }

    [DBus (name = "org.mpris.MediaPlayer2.Player")]
    public class MprisPlayerObj : Object {

        private string _status   = "Stopped";
        private int64  _position = 0;
        private GLib.Variant _metadata;
        private DBusConnection? _conn = null;

        public signal void seeked (int64 position);

        public string  playback_status { get { return _status; } }
        public double  rate            { get { return 1.0; } set {} }
        public double  minimum_rate    { get { return 1.0; } }
        public double  maximum_rate    { get { return 1.0; } }
        public double  volume          { get { return 1.0; } set {} }
        public int64   position        { get { return _position; } }
        public string  loop_status     { get { return "None"; } set {} }
        public bool    shuffle         { get { return false; } set {} }
        public bool    can_go_next     { get { return true; } }
        public bool    can_go_previous { get { return true; } }
        public bool    can_play        { get { return true; } }
        public bool    can_pause       { get { return true; } }
        public bool    can_seek        { get { return true; } }
        public bool    can_control     { get { return true; } }

        [DBus (signature = "a{sv}")]
        // `owned get` forces Vala to emit a g_variant_ref on read. Without
        // it the auto-generated DBus property serialiser eventually unrefs a
        // borrowed reference and trips
        //   g_atomic_ref_count_dec: assertion 'old_value > 0' failed
        // followed by SIGSEGV on the next access. Plain `get` on a refcounted
        // type returned by reference is a Vala/DBus footgun.
        public GLib.Variant metadata { owned get { return _metadata; } }

        public signal void play_pause_requested ();
        public signal void next_requested ();
        public signal void previous_requested ();
        public signal void play_requested ();
        public signal void pause_requested ();
        public signal void stop_requested ();
        public signal void seek_requested (int64 offset_us);
        public signal void position_requested (int64 position_us);

        public MprisPlayerObj () {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "mpris:trackid",
                new GLib.Variant.object_path ("/org/mpris/MediaPlayer2/TrackList/NoTrack"));
            _metadata = b.end ();
        }

        [DBus (visible = false)]
        public void set_dbus_connection (DBusConnection conn) { _conn = conn; }

        public void play_pause ()                                             throws DBusError, IOError { play_pause_requested (); }
        public void next ()                                                   throws DBusError, IOError { next_requested (); }
        public void previous ()                                               throws DBusError, IOError { previous_requested (); }
        public void play ()                                                   throws DBusError, IOError { play_requested (); }
        public void pause ()                                                  throws DBusError, IOError { pause_requested (); }
        public void stop ()                                                   throws DBusError, IOError { stop_requested (); }
        public void seek (int64 offset)                                       throws DBusError, IOError { seek_requested (offset); }
        public void set_position (GLib.ObjectPath track_id, int64 pos)       throws DBusError, IOError { position_requested (pos); }
        public void open_uri (string uri)                                     throws DBusError, IOError {}

        [DBus (visible = false)]
        public void set_playback (bool playing) {
            _status = playing ? "Playing" : "Paused";
            _emit_prop ("PlaybackStatus", new Variant.string (_status));
        }

        [DBus (visible = false)]
        public void set_stopped () {
            _status = "Stopped";
            _emit_prop ("PlaybackStatus", new Variant.string (_status));
        }

        [DBus (visible = false)]
        public void set_track (TrackInfo? track, string? art_url) {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            if (track != null) {
                b.add ("{sv}", "mpris:trackid",
                    new GLib.Variant.object_path (
                        "/org/mpris/MediaPlayer2/Track/%u".printf (track.uri.hash ())));
                b.add ("{sv}", "xesam:title",  new GLib.Variant.string (track.title));
                var artists = new string[] { track.artist };
                b.add ("{sv}", "xesam:artist", new GLib.Variant.strv (artists));
                if (track.album != "" && track.album != "Unknown Album")
                    b.add ("{sv}", "xesam:album", new GLib.Variant.string (track.album));
                if (track.duration > 0)
                    b.add ("{sv}", "mpris:length", new GLib.Variant.int64 (track.duration / 1000));
                if (art_url != null)
                    b.add ("{sv}", "mpris:artUrl", new GLib.Variant.string (art_url));
            } else {
                b.add ("{sv}", "mpris:trackid",
                    new GLib.Variant.object_path (
                        "/org/mpris/MediaPlayer2/TrackList/NoTrack"));
            }
            _metadata = b.end ();
            _emit_metadata ();
        }

        [DBus (visible = false)]
        public void set_position_ns (int64 pos_ns) {
            _position = pos_ns / 1000;
        }

        private void _emit_props (GLib.Variant props_dict) {
            if (_conn == null) return;
            var empty_strv = new GLib.Variant.array (GLib.VariantType.STRING,
                                                     new GLib.Variant[]{});
            var body = new GLib.Variant.tuple (new GLib.Variant[] {
                new GLib.Variant.string ("org.mpris.MediaPlayer2.Player"),
                props_dict,
                empty_strv
            });
            try {
                _conn.emit_signal (null, "/org/mpris/MediaPlayer2",
                    "org.freedesktop.DBus.Properties", "PropertiesChanged", body);
            } catch (Error e) { warning ("MPRIS PropertiesChanged: %s", e.message); }
        }

        private void _emit_prop (string prop, GLib.Variant val) {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", prop, val);
            _emit_props (b.end ());
        }

        private void _emit_metadata () {
            var b = new GLib.VariantBuilder (new GLib.VariantType ("a{sv}"));
            b.add ("{sv}", "Metadata", _metadata);
            _emit_props (b.end ());
        }
    }

    public class MprisExporter : Object {

        private MprisRoot      _root;
        private MprisPlayerObj _player;
        private uint           _own_id  = 0;
        private uint           _root_id = 0;
        private uint           _play_id = 0;
        private string?        _art_path = null;

        public MprisPlayerObj player_obj { get { return _player; } }

        public MprisExporter () {
            _root   = new MprisRoot ();
            _player = new MprisPlayerObj ();
        }

        public void start () {
            _own_id = Bus.own_name (BusType.SESSION,
                "org.mpris.MediaPlayer2.singularity-music",
                BusNameOwnerFlags.NONE,
                _on_acquired, null,
                () => warning ("MPRIS: could not own bus name"));
        }

        public void stop () {
            if (_own_id != 0) { Bus.unown_name (_own_id); _own_id = 0; }
        }

        private void _on_acquired (DBusConnection conn, string name) {
            _player.set_dbus_connection (conn);
            try {
                _root_id = conn.register_object ("/org/mpris/MediaPlayer2", _root);
                _play_id = conn.register_object ("/org/mpris/MediaPlayer2", _player);
            } catch (IOError e) {
                warning ("MPRIS register_object: %s", e.message);
            }
        }

        public void update_track (TrackInfo? track, Gdk.Texture? cover) {
            string? art_url = null;
            if (cover != null) {
                if (_art_path == null)
                    _art_path = GLib.Path.build_filename (
                        GLib.Environment.get_tmp_dir (), "singularity-music-cover.png");
                try { cover.save_to_png (_art_path); art_url = "file://" + _art_path; } catch {}
            }
            _player.set_track (track, art_url);
        }

        public void update_playback (bool playing) { _player.set_playback (playing); }
        public void set_stopped ()                  { _player.set_stopped (); }
        public void update_position (int64 pos_ns)  { _player.set_position_ns (pos_ns); }
    }
}
