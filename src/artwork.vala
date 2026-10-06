namespace Singularity.Apps.Music {

    public class Artwork : Object {
        private static Artwork? _default = null;
        private Gee.HashMap<string, Gdk.Texture> _memory = new Gee.HashMap<string, Gdk.Texture> ();
        private Gee.LinkedList<string> _order = new Gee.LinkedList<string> ();
        private Soup.Session? _session = null;
        private string _dir;

        public static Artwork get_default () {
            if (_default == null) _default = new Artwork ();
            return _default;
        }

        private Artwork () {
            _dir = Path.build_filename (Environment.get_user_cache_dir (), "dev.sinty.music", "artwork");
        }

        public void set_session (Soup.Session session) {
            _session = session;
        }

        private void remember (string url, Gdk.Texture tex) {
            _memory[url] = tex;
            _order.add (url);
            while (_order.size > 300) _memory.unset (_order.poll_head ());
        }

        public Gdk.Texture? cached (string url) {
            return _memory[url];
        }

        public async Gdk.Texture? load (string url, Cancellable? cancellable = null) {
            if (url == "") return null;
            var hit = _memory[url];
            if (hit != null) return hit;
            try {
                File file;
                if (url.has_prefix ("http://") || url.has_prefix ("https://")) {
                    string path = Path.build_filename (_dir, Checksum.compute_for_string (ChecksumType.MD5, url));
                    file = File.new_for_path (path);
                    if (!file.query_exists ()) {
                        if (_session == null) _session = new Soup.Session ();
                        var msg = new Soup.Message ("GET", url);
                        var bytes = yield _session.send_and_read_async (msg, Priority.LOW, cancellable);
                        if (msg.status_code != 200 || bytes.get_size () == 0) return null;
                        DirUtils.create_with_parents (_dir, 0700);
                        FileUtils.set_data (path, bytes.get_data ());
                    }
                } else {
                    file = File.new_for_uri (url);
                }
                var tex = yield load_scaled (file, cancellable);
                if (tex != null) remember (url, tex);
                return tex;
            } catch (Error e) {
                return null;
            }
        }

        private async Gdk.Texture? load_scaled (File file, Cancellable? cancellable) throws Error {
            var stream = yield file.read_async (Priority.LOW, cancellable);
            var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (stream, 512, 512, true, cancellable);
            return Gdk.Texture.for_pixbuf (pixbuf);
        }
    }
}
