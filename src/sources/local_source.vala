using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class LocalSource : Object, MediaSource, Browsable, Searchable, PlaybackResolver {
        public const string ID = "local";
        private const int PAGE = 200;

        public MusicLibrary library { get; construct; }

        public string id { owned get { return ID; } }
        public string title { owned get { return _("Library"); } }
        public string icon_name { owned get { return "folder-music-symbolic"; } }
        public MediaKind kinds { get { return MediaKind.AUDIO; } }
        public SourceFeatures features { get { return SourceFeatures.BROWSE | SourceFeatures.SEARCH | SourceFeatures.PLAY; } }
        public string? account_capability { owned get { return null; } }

        public LocalSource (MusicLibrary library) {
            Object (library: library);
            library.changed.connect (() => changed ());
        }

        public void activate (MediaHost host) {
        }

        public void deactivate () {
        }

        private static string cover_uri (string path) {
            return path != "" ? File.new_for_path (path).get_uri () : "";
        }

        public static MediaItem track_item (LibraryTrack t) {
            var it = new MediaItem (ID, "track:" + t.path, ItemKind.TRACK, t.title);
            it.artist = t.artist;
            it.album = t.album;
            it.subtitle = t.artist != "" ? t.artist : t.album;
            it.track_number = t.number;
            it.stream_uri = t.uri;
            it.image_url = cover_uri (t.cover);
            return it;
        }

        private MediaItem album_item (string key, Gee.List<LibraryTrack> tracks) {
            var first = tracks[0];
            var it = new MediaItem (ID, "album:" + key, ItemKind.ALBUM, first.album != "" ? first.album : _("Unknown Album"));
            it.artist = first.artist;
            it.subtitle = first.artist != ""
                ? _("%s, %s").printf (first.artist, ngettext ("%d song", "%d songs", tracks.size).printf (tracks.size))
                : ngettext ("%d song", "%d songs", tracks.size).printf (tracks.size);
            foreach (var t in tracks) {
                if (t.cover != "") {
                    it.image_url = cover_uri (t.cover);
                    break;
                }
            }
            return it;
        }

        private MediaItem artist_item (string name, int albums) {
            var it = new MediaItem (ID, "artist:" + name, ItemKind.ARTIST, name);
            it.subtitle = ngettext ("%d album", "%d albums", albums).printf (albums);
            return it;
        }

        private static int compare_tracks (LibraryTrack a, LibraryTrack b) {
            int c = strcmp (a.album_key.casefold (), b.album_key.casefold ());
            if (c != 0) return c;
            if (a.number != b.number) return a.number - b.number;
            return strcmp (a.path, b.path);
        }

        private Gee.ArrayList<LibraryTrack> sorted_tracks () {
            var list = new Gee.ArrayList<LibraryTrack> ();
            list.add_all (library.all);
            list.sort ((a, b) => {
                int c = strcmp (a.title.casefold (), b.title.casefold ());
                return c != 0 ? c : strcmp (a.path, b.path);
            });
            return list;
        }

        private Gee.TreeMap<string, Gee.ArrayList<LibraryTrack>> albums () {
            var map = new Gee.TreeMap<string, Gee.ArrayList<LibraryTrack>> ((a, b) => strcmp (a.casefold (), b.casefold ()));
            foreach (var t in library.all) {
                if (!map.has_key (t.album_key)) map[t.album_key] = new Gee.ArrayList<LibraryTrack> ();
                map[t.album_key].add (t);
            }
            foreach (var l in map.values) l.sort (compare_tracks);
            return map;
        }

        private Gee.TreeMap<string, Gee.HashSet<string>> artists () {
            var map = new Gee.TreeMap<string, Gee.HashSet<string>> ((a, b) => strcmp (a.casefold (), b.casefold ()));
            foreach (var t in library.all) {
                if (t.artist == "") continue;
                if (!map.has_key (t.artist)) map[t.artist] = new Gee.HashSet<string> ();
                map[t.artist].add (t.album_key);
            }
            return map;
        }

        private MediaPage slice (MediaPage page, Gee.List<MediaItem> all, string? token) {
            int offset = Paging.offset_of (token);
            for (int i = offset; i < int.min (offset + PAGE, all.size); i++) page.add (all[i]);
            page.total = all.size;
            page.next_token = Paging.next_of (offset, page.items.size, all.size);
            return page;
        }

        private MediaPage empty_library () {
            var page = new MediaPage (_("Library"));
            page.notice = _("Songs in %s appear here.").printf (library.root_folder ());
            page.action_label = _("Open Files");
            page.action_uri = "music:open-files";
            return page;
        }

        public async MediaPage browse (string? node, string? token, Cancellable? cancellable) throws Error {
            yield library.refresh ();
            if (cancellable != null && cancellable.is_cancelled ()) throw new IOError.CANCELLED ("Cancelled");
            if (node == null || node == "") {
                var root = new MediaPage (_("Library"));
                var songs = new MediaItem (ID, "songs", ItemKind.FOLDER, _("Songs"));
                songs.subtitle = ngettext ("%d song", "%d songs", library.all.size).printf (library.all.size);
                root.add (songs);
                root.add (new MediaItem (ID, "albums", ItemKind.FOLDER, _("Albums")));
                root.add (new MediaItem (ID, "artists", ItemKind.FOLDER, _("Artists")));
                return root;
            }
            if (library.all.size == 0 && (node == "songs" || node == "albums" || node == "artists")) return empty_library ();
            var items = new Gee.ArrayList<MediaItem> ();
            if (node == "songs") {
                foreach (var t in sorted_tracks ()) items.add (track_item (t));
                return slice (new MediaPage (_("Songs")), items, token);
            }
            if (node == "albums") {
                foreach (var e in albums ().entries) items.add (album_item (e.key, e.value));
                return slice (new MediaPage (_("Albums")), items, token);
            }
            if (node == "artists") {
                foreach (var e in artists ().entries) items.add (artist_item (e.key, e.value.size));
                return slice (new MediaPage (_("Artists")), items, token);
            }
            if (node.has_prefix ("album:")) {
                string key = node.substring (6);
                var tracks = albums ()[key];
                if (tracks == null) throw new MediaError.NOT_FOUND (_("The album is no longer in the library"));
                foreach (var t in tracks) items.add (track_item (t));
                var page = slice (new MediaPage (tracks[0].album != "" ? tracks[0].album : _("Unknown Album")), items, token);
                return page;
            }
            if (node.has_prefix ("artist:")) {
                string name = node.substring (7);
                foreach (var e in albums ().entries) {
                    if (e.value[0].artist == name) items.add (album_item (e.key, e.value));
                }
                if (items.size == 0) throw new MediaError.NOT_FOUND (_("The artist is no longer in the library"));
                return slice (new MediaPage (name), items, token);
            }
            throw new MediaError.NOT_FOUND (_("Nothing to show here"));
        }

        private static bool matches (string haystack, string[] terms) {
            string h = haystack.casefold ();
            foreach (var term in terms) if (!h.contains (term.casefold ())) return false;
            return true;
        }

        public async MediaPage search (string query, MediaKind kinds, string? token, Cancellable? cancellable) throws Error {
            yield library.refresh ();
            string[] terms = {};
            foreach (var t in query.split (" ")) if (t.strip () != "") terms += t.strip ();
            var items = new Gee.ArrayList<MediaItem> ();
            if (terms.length == 0) return new MediaPage (_("Results"));
            foreach (var e in albums ().entries) {
                var first = e.value[0];
                if (matches (first.album + " " + first.artist, terms)) items.add (album_item (e.key, e.value));
            }
            foreach (var e in artists ().entries) {
                if (matches (e.key, terms)) items.add (artist_item (e.key, e.value.size));
            }
            foreach (var t in sorted_tracks ()) {
                if (matches (t.title + " " + t.artist + " " + t.album, terms)) items.add (track_item (t));
            }
            return slice (new MediaPage (_("Results")), items, token);
        }

        public async Playback resolve (MediaItem item, Cancellable? cancellable) throws Error {
            if (item.stream_uri == "") throw new MediaError.NOT_FOUND (_("The file is missing"));
            return Playback.stream (item.stream_uri);
        }
    }
}
