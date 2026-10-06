using GLib;
using Gee;

namespace Singularity.Apps.Music {

    public class LibrarySearch : Singularity.SearchProviderService {
        private weak MusicApp app;
        public MusicLibrary library { get; private set; default = new MusicLibrary (); }

        public LibrarySearch (MusicApp app) {
            this.app = app;
        }

        private static bool matches (string haystack, string[] terms) {
            string h = haystack.casefold ();
            foreach (var term in terms) {
                if (!h.contains (term.casefold ())) return false;
            }
            return true;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            if (terms.length == 0 || string.joinv ("", terms).char_count () < 2) return {};
            var waiting = true;
            library.refresh.begin ((o, r) => {
                library.refresh.end (r);
                if (waiting) get_initial_results.callback ();
            });
            uint timer = Timeout.add (1800, () => {
                if (waiting) get_initial_results.callback ();
                return Source.REMOVE;
            });
            yield;
            waiting = false;
            Source.remove (timer);
            return find (terms);
        }

        public override async string[] get_subsearch_results (string[] previous, string[] terms, Cancellable? cancellable) throws Error {
            return find (terms);
        }

        private string[] find (string[] terms) {
            var artists = new ArrayList<string> ();
            var albums = new ArrayList<string> ();
            var songs = new ArrayList<string> ();
            foreach (var t in library.all) {
                if (t.artist != "" && matches (t.artist, terms) && !artists.contains ("r:" + t.artist)) artists.add ("r:" + t.artist);
                if (matches (t.album + " " + t.artist, terms) && !albums.contains ("a:" + t.album_key)) albums.add ("a:" + t.album_key);
                if (matches (t.title + " " + t.artist + " " + t.album, terms)) songs.add ("t:" + t.path);
            }
            albums.sort ();
            artists.sort ();
            songs.sort ((a, b) => compare_tracks (library_track (a.substring (2)), library_track (b.substring (2))));
            string[] ids = {};
            foreach (var id in albums) ids += id;
            foreach (var id in artists) ids += id;
            foreach (var id in songs) ids += id;
            if (ids.length > 20) ids = ids[0:20];
            return ids;
        }

        private LibraryTrack? library_track (string path) {
            foreach (var t in library.all) if (t.path == path) return t;
            return null;
        }

        private static int compare_tracks (LibraryTrack? a, LibraryTrack? b) {
            if (a == null || b == null) return 0;
            int c = strcmp (a.album_key, b.album_key);
            if (c != 0) return c;
            if (a.number != b.number) return a.number - b.number;
            return strcmp (a.path, b.path);
        }

        private ArrayList<LibraryTrack> tracks_for (string id) {
            var list = new ArrayList<LibraryTrack> ();
            string key = id.substring (2);
            foreach (var t in library.all) {
                if ((id.has_prefix ("t:") && t.path == key)
                    || (id.has_prefix ("a:") && t.album_key == key)
                    || (id.has_prefix ("r:") && t.artist == key))
                    list.add (t);
            }
            list.sort ((a, b) => compare_tracks (a, b));
            return list;
        }

        private static GLib.Icon? cover_icon (string cover) {
            if (cover == "") return null;
            return new FileIcon (File.new_for_path (cover));
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            foreach (var id in ids) {
                var list = tracks_for (id);
                if (list.size == 0) continue;
                var first = list[0];
                Singularity.SearchResultMeta meta;
                if (id.has_prefix ("t:")) {
                    meta = new Singularity.SearchResultMeta (id, first.title);
                    string[] parts = {};
                    if (first.artist != "") parts += first.artist;
                    if (first.album != "") parts += first.album;
                    meta.description = string.joinv (", ", parts);
                    meta.score = 1.0;
                } else if (id.has_prefix ("a:")) {
                    meta = new Singularity.SearchResultMeta (id, first.album);
                    string count = ngettext ("%d song", "%d songs", list.size).printf (list.size);
                    meta.description = first.artist != "" ? _("Album by %s, %s").printf (first.artist, count) : _("Album, %s").printf (count);
                    meta.score = 3.0;
                } else {
                    meta = new Singularity.SearchResultMeta (id, first.artist);
                    var albums = new HashSet<string> ();
                    foreach (var t in list) albums.add (t.album);
                    meta.description = ngettext ("Artist, %d album", "Artist, %d albums", albums.size).printf (albums.size);
                    meta.score = 2.0;
                }
                string cover = "";
                foreach (var t in list) if (t.cover != "") { cover = t.cover; break; }
                meta.icon = cover_icon (cover);
                meta.add_action ("enqueue", _("Add to Playlist"), "list-add-symbolic");
                metas += meta;
            }
            return metas;
        }

        private string[] uris_for (string id) {
            string[] uris = {};
            foreach (var t in tracks_for (id)) uris += t.uri;
            return uris;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            var uris = uris_for (id);
            if (uris.length > 0) app.play_uris (uris, true);
            return null;
        }

        public override async Singularity.SearchActivationReply? activate_action (string id, string action, string[] terms, uint32 timestamp) throws Error {
            var uris = uris_for (id);
            if (action == "enqueue" && uris.length > 0) app.play_uris (uris, false);
            return null;
        }
    }
}
