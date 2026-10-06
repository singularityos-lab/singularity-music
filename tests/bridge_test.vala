using Singularity.Apps.Music;

[DBus (name = "org.mpris.MediaPlayer2.Player")]
class FakeSpotifyPlayer : Object {
    public int toggles = 0;
    public int nexts = 0;
    public int64 set_to = -1;
    public string playback_status { owned get; set; default = "Paused"; }
    public bool can_control { get { return true; } }
    [DBus (signature = "a{sv}")]
    public Variant metadata { owned get; set; }
    public int64 position { get { return 42000000; } }

    public FakeSpotifyPlayer () {
        var b = new VariantBuilder (new VariantType ("a{sv}"));
        b.add ("{sv}", "mpris:trackid", new Variant.object_path ("/com/spotify/track/abc"));
        b.add ("{sv}", "xesam:title", new Variant.string ("Paper Moon"));
        b.add ("{sv}", "xesam:artist", new Variant.strv ({ "The Testers" }));
        b.add ("{sv}", "xesam:album", new Variant.string ("Bridges"));
        b.add ("{sv}", "mpris:length", new Variant.uint64 (180000000));
        b.add ("{sv}", "mpris:artUrl", new Variant.string ("https://i.scdn.co/image/abc"));
        metadata = b.end ();
    }

    public void play_pause () throws DBusError, IOError {
        toggles++;
        playback_status = playback_status == "Playing" ? "Paused" : "Playing";
    }

    public void next () throws DBusError, IOError {
        nexts++;
    }

    public void previous () throws DBusError, IOError {
    }

    public void set_position (ObjectPath track, int64 pos) throws DBusError, IOError {
        set_to = pos;
    }
}

[DBus (name = "org.mpris.MediaPlayer2")]
class FakeSpotifyRoot : Object {
    public int raised = 0;
    public string identity { owned get { return "Spotify"; } }
    public void raise () throws DBusError, IOError {
        raised++;
    }
}

void emit_changed (DBusConnection conn, string prop, Variant value) {
    var b = new VariantBuilder (new VariantType ("a{sv}"));
    b.add ("{sv}", prop, value);
    try {
        conn.emit_signal (null, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged",
            new Variant ("(sa{sv}as)", "org.mpris.MediaPlayer2.Player", b, new VariantBuilder (new VariantType ("as"))));
    } catch (Error e) {
        error ("%s", e.message);
    }
}

void wait_until (owned SourceFunc cond, int ms = 3000) {
    var ctx = MainContext.default ();
    int64 end = get_monotonic_time () + ms * 1000;
    while (!cond () && get_monotonic_time () < end) ctx.iteration (false);
    assert (cond ());
}

void test_bridge () {
    try {
        var conn = Bus.get_sync (BusType.SESSION);
        var bridge = new SpotifyBridge ();
        assert (!bridge.running);
        var player = new FakeSpotifyPlayer ();
        var root = new FakeSpotifyRoot ();
        conn.register_object ("/org/mpris/MediaPlayer2", player);
        conn.register_object ("/org/mpris/MediaPlayer2", root);
        uint owner = Bus.own_name_on_connection (conn, SpotifyBridge.BUS_NAME, BusNameOwnerFlags.NONE);
        wait_until (() => bridge.running && bridge.title == "Paper Moon");
        assert (bridge.artist == "The Testers" && bridge.album == "Bridges" && bridge.length_us == 180000000 && !bridge.playing);
        assert (bridge.art_url == "https://i.scdn.co/image/abc");
        bridge.play_pause ();
        wait_until (() => player.toggles == 1);
        emit_changed (conn, "PlaybackStatus", new Variant.string ("Playing"));
        wait_until (() => bridge.playing);
        bridge.next ();
        wait_until (() => player.nexts == 1);
        bridge.seek_to (60000000);
        wait_until (() => player.set_to == 60000000);
        wait_until (() => bridge.position_us == 42000000);
        bridge.raise_or_launch (null);
        wait_until (() => root.raised == 1);
        Bus.unown_name (owner);
        wait_until (() => !bridge.running);
        assert (bridge.title == "");
    } catch (Error e) {
        error ("bridge: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/music/spotify-bridge", test_bridge);
    return Test.run ();
}
