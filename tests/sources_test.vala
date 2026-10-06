using Singularity.Apps.Music;
using Singularity.MediaSources;

class FakeRemote : Object, RemotePlayer {
    public PlaybackState st = PlaybackState.STOPPED;
    public MediaItem? cur = null;
    public int64 pos = 0;
    public bool active = false;
    public PlaybackState state { get { return st; } }
    public MediaItem? current { owned get { return cur; } }
    public int64 position_ms { get { return pos; } }
    public int64 duration_ms { get { return cur != null ? cur.duration_ms : 0; } }
    public double volume { get { return 1; } }
    public RemoteDevice? device { owned get { return new RemoteDevice ("d", "Speaker"); } }
    public async Gee.List<RemoteDevice> devices (Cancellable? c) throws Error { return new Gee.ArrayList<RemoteDevice> (); }
    public async void transfer (string id, bool play) throws Error {}
    public async void play_item (MediaItem item, MediaItem? context) throws Error {
        cur = item;
        st = PlaybackState.PLAYING;
        pos = 1000;
        state_changed ();
    }
    public async void resume () throws Error { st = PlaybackState.PLAYING; state_changed (); }
    public async void pause () throws Error { st = PlaybackState.PAUSED; state_changed (); }
    public async void next () throws Error {}
    public async void previous () throws Error {}
    public async void seek (int64 p) throws Error { pos = p; state_changed (); }
    public async void set_volume (double v) throws Error {}
    public void set_active (bool a) { active = a; }
}

string make_library () {
    string dir = "";
    try {
        dir = DirUtils.make_tmp ("music-test-XXXXXX");
    } catch (Error e) {
        assert_not_reached ();
    }
    string[] args = {};
    unowned string[] a = args;
    Gst.init (ref a);
    string[,] spec = {
        { "Northfield Quartet", "Glass Harbor", "Low Tide", "1" },
        { "Northfield Quartet", "Glass Harbor", "Lantern Walk", "2" },
        { "Mira Okafor", "Paper Satellites", "Kitebound", "1" }
    };
    for (int i = 0; i < 3; i++) {
        string d = Path.build_filename (dir, spec[i, 0], spec[i, 1]);
        DirUtils.create_with_parents (d, 0700);
        string path = Path.build_filename (d, "%s.ogg".printf (spec[i, 2]));
        string desc = "audiotestsrc num-buffers=20 ! audioconvert ! taginject tags=\"title=\\\"%s\\\",artist=\\\"%s\\\",album=\\\"%s\\\"\" ! vorbisenc ! oggmux ! filesink location=\"%s\"".printf (spec[i, 2], spec[i, 0], spec[i, 1], path);
        try {
            var p = Gst.parse_launch (desc);
            p.set_state (Gst.State.PLAYING);
            p.get_bus ().timed_pop_filtered (10 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            p.set_state (Gst.State.NULL);
        } catch (Error e) {
            error ("gst: %s", e.message);
        }
    }
    return dir;
}

async void local_case () {
    var lib = new MusicLibrary ();
    lib.folder = make_library ();
    var src = new LocalSource (lib);
    try {
        var root = yield src.browse (null, null, null);
        assert (root.items.size == 3 && root.items[0].subtitle == "3 songs");
        var songs = yield src.browse ("songs", null, null);
        assert (songs.items.size == 3);
        assert (songs.items[0].title == "Kitebound" && songs.items[1].title == "Lantern Walk");
        var albums = yield src.browse ("albums", null, null);
        assert (albums.items.size == 2 && albums.items[0].kind == ItemKind.ALBUM);
        var harbor = albums.items[0].title == "Glass Harbor" ? albums.items[0] : albums.items[1];
        var tracks = yield src.browse (harbor.id, null, null);
        assert (tracks.items.size == 2 && tracks.title == "Glass Harbor");
        var artists = yield src.browse ("artists", null, null);
        assert (artists.items.size == 2);
        var by = yield src.browse (artists.items[1].id, null, null);
        assert (by.items.size == 1 && by.items[0].kind == ItemKind.ALBUM);
        var found = yield src.search ("tide", MediaKind.AUDIO, null, null);
        assert (found.items.size == 1 && found.items[0].title == "Low Tide");
        var pb = yield src.resolve (found.items[0], null);
        assert (pb.kind == PlaybackKind.STREAM && pb.uri.has_prefix ("file://") && pb.uri.has_suffix ("Low%20Tide.ogg"));
        var t = TrackInfo.from_item (found.items[0]);
        assert (!t.resolved && t.source_id == "local" && t.artist == "Northfield Quartet");
        var back = t.to_item ();
        assert (back == found.items[0]);
    } catch (Error e) {
        error ("local: %s", e.message);
    }
    lib.folder = Path.build_filename (Environment.get_tmp_dir (), "music-test-missing");
    lib.invalidate ();
    try {
        var empty = yield src.browse ("songs", null, null);
        assert (empty.items.size == 0 && empty.action_uri == "music:open-files");
    } catch (Error e) {
        error ("empty: %s", e.message);
    }
}

void test_local () {
    var loop = new MainLoop ();
    local_case.begin ((o, r) => {
        local_case.end (r);
        loop.quit ();
    });
    loop.run ();
}

void test_remote_backend () {
    var fake = new FakeRemote ();
    var backend = new RemoteBackend (fake);
    var states = new Gee.ArrayList<bool> ();
    backend.playing_changed.connect ((p) => states.add (p));
    var item = new MediaItem ("spotify", "x/track/1", ItemKind.TRACK, "Song");
    item.duration_ms = 200000;
    var loop = new MainLoop ();
    backend.start (item, null);
    assert (fake.active);
    Timeout.add (100, () => {
        assert (backend.is_playing && states.size == 1 && states[0]);
        assert (backend.get_position () >= 1000000000 && backend.get_duration () == 200000000000);
        backend.pause ();
        return Source.REMOVE;
    });
    Timeout.add (300, () => {
        assert (!backend.is_playing && states.size == 2 && !states[1]);
        backend.seek (5000000000);
        return Source.REMOVE;
    });
    Timeout.add (500, () => {
        assert (fake.pos == 5000);
        backend.stop ();
        assert (!fake.active);
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
}

void test_pipe_player () {
    string dir = "";
    try {
        dir = DirUtils.make_tmp ("music-pipe-XXXXXX");
    } catch (Error e) {
        assert_not_reached ();
    }
    string fifo = Path.build_filename (dir, "pcm");
    assert (Posix.mkfifo (fifo, 0600) == 0);
    Environment.set_variable ("SINGULARITY_MUSIC_AUDIO_SINK", "fakesink sync=false", true);
    var p = new PipeAudioPlayer (fifo, 44100, 2);
    p.start ();
    uint8[] chunk = new uint8[44100];
    for (int round = 0; round < 2; round++) {
        new Thread<void> ("writer", () => {
            var f = FileStream.open (fifo, "w");
            f.write (chunk);
            f.flush ();
        });
        var ctx = MainContext.default ();
        int64 end = get_monotonic_time () + 5000000;
        int64 want = (round + 1) * 44100;
        while (p.bytes_seen < want - 4096 && get_monotonic_time () < end) ctx.iteration (false);
        assert (p.bytes_seen >= want - 4096);
    }
    p.set_volume (0.3);
    p.stop ();
    FileUtils.unlink (fifo);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/music/local-source", test_local);
    Test.add_func ("/music/remote-backend", test_remote_backend);
    Test.add_func ("/music/pipe-player", test_pipe_player);
    return Test.run ();
}
