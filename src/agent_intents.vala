namespace Singularity.Apps.Music {

    internal class MusicIntents : Object {
        private const string[] CONTROLS = { "play", "pause", "toggle", "stop", "next", "previous", "seek" };
        private const string[] REPEATS = { "none", "all", "one" };
        private const int DEFAULT_LIMIT = 50;

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static double seconds (int64 ns) {
            return ns <= 0 ? 0.0 : Math.round (ns / 100000000.0) / 10.0;
        }

        private static Json.Object track (TrackInfo t) {
            var o = new Json.Object ();
            o.set_string_member ("title", t.title);
            o.set_string_member ("artist", t.artist);
            o.set_string_member ("album", t.album);
            o.set_string_member ("uri", t.uri);
            if (t.duration > 0) o.set_double_member ("duration", seconds (t.duration));
            return o;
        }

        private static Json.Node status (MusicWindow w) {
            var o = new Json.Object ();
            o.set_boolean_member ("playing", w.playing);
            var current = w.playing_track;
            if (current != null) {
                o.set_object_member ("track", track (current));
                o.set_double_member ("position", seconds (w.position));
                o.set_double_member ("duration", seconds (w.duration));
            }
            o.set_boolean_member ("shuffle", w.queue.shuffle);
            o.set_string_member ("repeat", REPEATS[w.repeat_mode.clamp (0, 2)]);
            o.set_double_member ("volume", Math.round (w.volume * 100) / 100.0);
            o.set_int_member ("current_index", w.queue.current_index);
            var queue = new Json.Array ();
            for (int i = 0; i < w.queue.count; i++) {
                var t = w.queue.get_track (i);
                if (t == null) continue;
                var to = track (t);
                to.set_int_member ("index", i);
                queue.add_object_element (to);
            }
            o.set_array_member ("queue", queue);
            return obj (o);
        }

        private static bool matches (LibraryTrack t, string[] words) {
            string hay = (t.title + " " + t.artist + " " + t.album + " " + Path.get_basename (t.path)).casefold ();
            foreach (var w in words) if (!hay.contains (w)) return false;
            return true;
        }

        private static string[] words (string query) {
            string[] out = {};
            foreach (var w in query.casefold ().split (" ")) if (w.strip () != "") out += w.strip ();
            return out;
        }

        private static Gee.ArrayList<LibraryTrack> find (MusicLibrary library, Json.Object args) {
            var found = new Gee.ArrayList<LibraryTrack> ();
            string[] q = words (text (args, "query"));
            string artist = text (args, "artist").casefold ();
            string album = text (args, "album").casefold ();
            foreach (var t in library.all) {
                if (artist != "" && !t.artist.casefold ().contains (artist)) continue;
                if (album != "" && !t.album.casefold ().contains (album)) continue;
                if (!matches (t, q)) continue;
                found.add (t);
            }
            found.sort ((a, b) => {
                int c = strcmp (a.artist.casefold (), b.artist.casefold ());
                if (c == 0) c = strcmp (a.album.casefold (), b.album.casefold ());
                if (c == 0) c = a.number - b.number;
                if (c == 0) c = strcmp (a.path, b.path);
                return c;
            });
            return found;
        }

        private static int limit (Json.Object args) {
            if (!args.has_member ("limit")) return DEFAULT_LIMIT;
            return (int) args.get_int_member ("limit").clamp (1, 500);
        }

        private static Json.Node play (MusicApp app, Json.Object args) throws Error {
            string[] uris = {};
            if (args.has_member ("paths")) {
                foreach (var n in args.get_array_member ("paths").get_elements ()) {
                    string p = n.get_string ();
                    if (!FileUtils.test (p, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("%s does not exist", p);
                    uris += File.new_for_path (p).get_uri ();
                }
            } else if (args.has_member ("query") || args.has_member ("artist") || args.has_member ("album")) {
                foreach (var t in find (app.library, args)) uris += t.uri;
                if (uris.length == 0) throw new IOError.NOT_FOUND ("no song in the library matches");
            } else {
                throw new IOError.INVALID_ARGUMENT ("give paths, or words, an artist or an album to look for");
            }
            if (uris.length == 0) throw new IOError.INVALID_ARGUMENT ("paths is empty");
            var w = app.ensure_window ();
            if (args.has_member ("shuffle")) w.set_shuffle (args.get_boolean_member ("shuffle"));
            bool enqueue = args.has_member ("enqueue") && args.get_boolean_member ("enqueue");
            if (enqueue) w.open_uris (uris);
            else w.play_uris (uris);
            return status (w);
        }

        private static Json.Node search (MusicApp app, Json.Object args) {
            var found = find (app.library, args);
            int max = limit (args);
            var o = new Json.Object ();
            o.set_int_member ("total", found.size);
            var tracks = new Json.Array ();
            for (int i = 0; i < found.size && i < max; i++) {
                var t = found[i];
                var to = new Json.Object ();
                to.set_string_member ("title", t.title);
                to.set_string_member ("artist", t.artist);
                to.set_string_member ("album", t.album);
                to.set_int_member ("number", t.number);
                to.set_string_member ("path", t.path);
                tracks.add_object_element (to);
            }
            o.set_array_member ("tracks", tracks);
            return obj (o);
        }

        internal static void install (MusicApp app) {
            var agent = app.agent;
            agent.add_intent ("music_status", "Read what is playing: the current song, position, shuffle, repeat, volume and the play queue.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => status (app.ensure_window ()));

            agent.add_async_intent ("music_search", "Search the songs in the Music folder by words, artist or album. Without filters it lists the library.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"artist\":{\"type\":\"string\"},\"album\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    app.library.settle.begin ((o, r) => {
                        app.library.settle.end (r);
                        reply (search (app, args), null);
                    });
                });

            agent.add_async_intent ("music_play", "Play songs: files by path, or the songs of the library that match words, artist or album. Replaces the queue unless enqueue is true.",
                "{\"type\":\"object\",\"properties\":{\"paths\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"query\":{\"type\":\"string\"},\"artist\":{\"type\":\"string\"},\"album\":{\"type\":\"string\"},\"shuffle\":{\"type\":\"boolean\"},\"enqueue\":{\"type\":\"boolean\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    app.library.settle.begin ((o, r) => {
                        app.library.settle.end (r);
                        try {
                            reply (play (app, args), null);
                        } catch (Error e) {
                            reply (null, e);
                        }
                    });
                });

            agent.add_intent ("music_control", "Control playback: play, pause, toggle, stop, next, previous, or seek to a position in seconds.",
                "{\"type\":\"object\",\"properties\":{\"action\":{\"type\":\"string\",\"enum\":" + list (CONTROLS) + "},\"position\":{\"type\":\"number\"}},\"required\":[\"action\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string action = text (args, "action");
                    if (!(action in CONTROLS)) throw new IOError.INVALID_ARGUMENT ("unknown action %s", action);
                    var w = app.ensure_window ();
                    if (action != "stop" && w.playing_track == null) throw new IOError.FAILED ("nothing is in the queue");
                    switch (action) {
                        case "play": w.set_playing (true); break;
                        case "pause": w.set_playing (false); break;
                        case "toggle": w.set_playing (!w.playing); break;
                        case "stop": w.stop_playback (); break;
                        case "next": w.next_track (); break;
                        case "previous": w.previous_track (); break;
                        default:
                            if (!args.has_member ("position")) throw new IOError.INVALID_ARGUMENT ("seek needs a position in seconds");
                            w.seek_to ((int64) (args.get_double_member ("position") * 1000000000.0));
                            break;
                    }
                    return status (w);
                });

            agent.add_intent ("music_queue", "Play the song at a position of the queue, remove it, or clear the whole queue.",
                "{\"type\":\"object\",\"properties\":{\"play\":{\"type\":\"integer\"},\"remove\":{\"type\":\"integer\"},\"clear\":{\"type\":\"boolean\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = app.ensure_window ();
                    if (args.has_member ("clear") && args.get_boolean_member ("clear")) {
                        w.queue.clear ();
                        return status (w);
                    }
                    string key = args.has_member ("play") ? "play" : (args.has_member ("remove") ? "remove" : "");
                    if (key == "") throw new IOError.INVALID_ARGUMENT ("give play, remove or clear");
                    int index = (int) args.get_int_member (key);
                    if (index < 0 || index >= w.queue.count) throw new IOError.NOT_FOUND ("the queue has no song at %d", index);
                    if (key == "play") w.play_index (index);
                    else w.queue.remove_at (index);
                    return status (w);
                });

            agent.add_intent ("music_mode", "Change shuffle, repeat (none, all, one) and the volume from 0 to 1.",
                "{\"type\":\"object\",\"properties\":{\"shuffle\":{\"type\":\"boolean\"},\"repeat\":{\"type\":\"string\",\"enum\":" + list (REPEATS) + "},\"volume\":{\"type\":\"number\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = app.ensure_window ();
                    if (args.has_member ("repeat")) {
                        string r = text (args, "repeat");
                        int mode = -1;
                        for (int i = 0; i < REPEATS.length; i++) if (REPEATS[i] == r) mode = i;
                        if (mode < 0) throw new IOError.INVALID_ARGUMENT ("unknown repeat mode %s", r);
                        w.set_repeat_mode (mode);
                    }
                    if (args.has_member ("shuffle")) w.set_shuffle (args.get_boolean_member ("shuffle"));
                    if (args.has_member ("volume")) w.set_volume (args.get_double_member ("volume"));
                    return status (w);
                });
        }
    }
}
