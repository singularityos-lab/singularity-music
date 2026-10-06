using GLib;
using Gee;

namespace Singularity.Apps.Music {

    public class LibraryTrack : Object {
        public string path = "";
        public int64 mtime = 0;
        public string title = "";
        public string artist = "";
        public string album = "";
        public int number = 0;
        public string cover = "";

        public string uri { owned get { return File.new_for_path (path).get_uri (); } }
        public string album_key { owned get { return artist + "\x1f" + album; } }
    }

    public class MusicLibrary : Object {
        private const string[] COVER_NAMES = { "cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png", "album.jpg" };

        private HashMap<string, LibraryTrack> tracks = new HashMap<string, LibraryTrack> ();
        private string cache_dir;
        private string cache_file;
        private int64 last_scan = 0;
        private bool scanning = false;

        public MusicLibrary () {
            cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-music");
            cache_file = Path.build_filename (cache_dir, "library.ini");
            load ();
        }

        public Collection<LibraryTrack> all { owned get { return tracks.values; } }
        public string folder { get; set; default = ""; }
        public signal void changed ();

        public string root_folder () {
            if (folder.strip () != "") return folder.strip ();
            string? root = Environment.get_user_special_dir (UserDirectory.MUSIC);
            if (root == null || root == Environment.get_home_dir ())
                root = Path.build_filename (Environment.get_home_dir (), "Music");
            return root;
        }

        public void invalidate () {
            last_scan = 0;
        }

        private void load () {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (cache_file, KeyFileFlags.NONE);
            } catch (Error e) {
                return;
            }
            foreach (var group in kf.get_groups ()) {
                try {
                    var t = new LibraryTrack ();
                    t.path = group;
                    t.mtime = kf.get_int64 (group, "mtime");
                    t.title = kf.get_string (group, "title");
                    t.artist = kf.get_string (group, "artist");
                    t.album = kf.get_string (group, "album");
                    t.number = kf.get_integer (group, "number");
                    t.cover = kf.get_string (group, "cover");
                    tracks[group] = t;
                } catch (Error e) {}
            }
        }

        private void save () {
            var kf = new KeyFile ();
            foreach (var t in tracks.values) {
                kf.set_int64 (t.path, "mtime", t.mtime);
                kf.set_string (t.path, "title", t.title);
                kf.set_string (t.path, "artist", t.artist);
                kf.set_string (t.path, "album", t.album);
                kf.set_integer (t.path, "number", t.number);
                kf.set_string (t.path, "cover", t.cover);
            }
            try {
                DirUtils.create_with_parents (cache_dir, 0700);
                kf.save_to_file (cache_file);
            } catch (Error e) {
                warning ("music library: %s", e.message);
            }
        }

        public async void refresh () {
            int64 now = get_monotonic_time ();
            if (scanning || (last_scan != 0 && now - last_scan < 60 * TimeSpan.SECOND)) return;
            scanning = true;
            string root = root_folder ();
            var known = new HashMap<string, LibraryTrack> ();
            foreach (var e in tracks.entries) known[e.key] = e.value;
            HashMap<string, LibraryTrack>? found = null;
            SourceFunc cb = refresh.callback;
            new Thread<void> ("music-library", () => {
                found = scan (root, known);
                Idle.add ((owned) cb);
            });
            yield;
            bool differs = found.size != tracks.size;
            if (!differs) {
                foreach (var e in found.entries) {
                    var old = tracks[e.key];
                    if (old == null || old.mtime != e.value.mtime) {
                        differs = true;
                        break;
                    }
                }
            }
            tracks = found;
            last_scan = get_monotonic_time ();
            scanning = false;
            save ();
            if (differs) changed ();
        }

        private HashMap<string, LibraryTrack> scan (string root, HashMap<string, LibraryTrack> known) {
            var result = new HashMap<string, LibraryTrack> ();
            string[] no_args = {};
            unowned string[] args = no_args;
            Gst.init (ref args);
            Gst.PbUtils.Discoverer? discoverer = null;
            try {
                discoverer = new Gst.PbUtils.Discoverer (3 * Gst.SECOND);
            } catch (Error e) {
                warning ("music library: %s", e.message);
            }
            var dirs = new ArrayQueue<File> ();
            dirs.offer (File.new_for_path (root));
            int budget = 5000;
            while (!dirs.is_empty && budget > 0) {
                var dir = dirs.poll ();
                try {
                    var en = dir.enumerate_children ("standard::name,standard::type,standard::content-type,standard::is-hidden,time::modified",
                        FileQueryInfoFlags.NONE);
                    FileInfo? info;
                    while ((info = en.next_file ()) != null && budget > 0) {
                        if (info.get_is_hidden ()) continue;
                        var child = dir.get_child (info.get_name ());
                        if (info.get_file_type () == FileType.DIRECTORY) {
                            dirs.offer (child);
                            continue;
                        }
                        string? ct = info.get_content_type ();
                        if (ct == null || !(ct.has_prefix ("audio/") || ContentType.is_a (ct, "audio/mpeg"))) continue;
                        budget--;
                        string path = child.get_path ();
                        int64 mtime = info.get_modification_date_time ()?.to_unix () ?? 0;
                        var cached = known[path];
                        if (cached != null && cached.mtime == mtime) {
                            result[path] = cached;
                            continue;
                        }
                        result[path] = read_track (discoverer, child, mtime);
                    }
                } catch (Error e) {}
            }
            return result;
        }

        private LibraryTrack read_track (Gst.PbUtils.Discoverer? discoverer, File file, int64 mtime) {
            var t = new LibraryTrack ();
            t.path = file.get_path ();
            t.mtime = mtime;
            string name = file.get_basename ();
            int dot = name.last_index_of_char ('.');
            t.title = dot > 0 ? name.substring (0, dot) : name;
            t.album = file.get_parent ().get_basename ();
            Gst.Sample? image = null;
            if (discoverer != null) {
                try {
                    var info = discoverer.discover_uri (file.get_uri ());
                    var tags = info.get_tags ();
                    if (tags != null) {
                        string s;
                        if (tags.get_string (Gst.Tags.TITLE, out s) && s.strip () != "") t.title = s.strip ();
                        if (tags.get_string (Gst.Tags.ARTIST, out s) && s.strip () != "") t.artist = s.strip ();
                        if (tags.get_string (Gst.Tags.ALBUM, out s) && s.strip () != "") t.album = s.strip ();
                        uint n;
                        if (tags.get_uint (Gst.Tags.TRACK_NUMBER, out n)) t.number = (int) n;
                        if (!tags.get_sample (Gst.Tags.IMAGE, out image)) tags.get_sample (Gst.Tags.PREVIEW_IMAGE, out image);
                    }
                } catch (Error e) {}
            }
            t.cover = find_cover (file, t, image);
            return t;
        }

        private string find_cover (File file, LibraryTrack t, Gst.Sample? image) {
            if (image != null && image.get_buffer () != null) {
                string key = Checksum.compute_for_string (ChecksumType.MD5, t.album_key + "\n" + file.get_parent ().get_path ());
                string out_dir = Path.build_filename (cache_dir, "covers");
                string out_path = Path.build_filename (out_dir, key);
                if (FileUtils.test (out_path, FileTest.EXISTS)) return out_path;
                Gst.MapInfo map;
                var buffer = image.get_buffer ();
                if (buffer.map (out map, Gst.MapFlags.READ)) {
                    try {
                        DirUtils.create_with_parents (out_dir, 0700);
                        FileUtils.set_data (out_path, map.data);
                        buffer.unmap (map);
                        return out_path;
                    } catch (Error e) {
                        buffer.unmap (map);
                    }
                }
            }
            var parent = file.get_parent ();
            foreach (unowned string n in COVER_NAMES) {
                var c = parent.get_child (n);
                if (c.query_exists ()) return c.get_path ();
            }
            return "";
        }
    }
}
