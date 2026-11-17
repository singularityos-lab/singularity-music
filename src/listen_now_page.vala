using Gtk;
using Singularity.Widgets;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class ListenNowPage : Box {
        public signal void play_items (Gee.List<MediaItem> items, int start, bool shuffle);
        public signal void open_item (MediaItem item);

        private MediaSource? _source = null;
        private MediaHero _hero;
        private MediaShelf _recent;
        private MediaShelf _artists;
        private MediaItem? _hero_item = null;
        private Gee.ArrayList<MediaItem> _recent_items = new Gee.ArrayList<MediaItem> ();
        private Gee.ArrayList<MediaItem> _artist_items = new Gee.ArrayList<MediaItem> ();
        private Cancellable? _cancel = null;

        public ListenNowPage () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("music-listen-now");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var column = new Box (Orientation.VERTICAL, 28);
            column.margin_top = 16;
            column.margin_bottom = 24;
            column.margin_start = 24;
            column.margin_end = 24;
            var heading = new Label (_("Listen Now"));
            heading.xalign = 0;
            heading.add_css_class ("title-2");
            column.append (heading);

            _hero = new MediaHero ("singularity-music-album");
            _hero.eyebrow = _("Recently Added");
            _hero.primary_label = _("Play");
            _hero.secondary_label = _("Shuffle");
            _hero.primary_clicked.connect (() => play_album (_hero_item, false));
            _hero.secondary_clicked.connect (() => play_album (_hero_item, true));
            _hero.visible = false;
            column.append (_hero);

            _recent = new MediaShelf (_("Recently Added"));
            _recent.item_activated.connect ((i) => {
                if (i < _recent_items.size) open_item (_recent_items[(int) i]);
            });
            _recent.visible = false;
            column.append (_recent);

            _artists = new MediaShelf (_("Artists"), 132, true);
            _artists.item_activated.connect ((i) => {
                if (i < _artist_items.size) open_item (_artist_items[(int) i]);
            });
            _artists.visible = false;
            column.append (_artists);

            scroll.set_child (column);
            append (scroll);
        }

        public void set_source (MediaSource source) {
            _source = source;
            reload ();
        }

        public void reload () {
            var b = _source as Browsable;
            if (b == null) return;
            if (_cancel != null) _cancel.cancel ();
            _cancel = new Cancellable ();
            load.begin (b, _cancel);
        }

        private async void load (Browsable b, Cancellable cancel) {
            Gee.List<MediaItem> recent;
            Gee.List<MediaItem> artists;
            try {
                recent = (yield b.browse ("recent", null, cancel)).items;
                artists = (yield b.browse ("artists", null, cancel)).items;
            } catch (Error e) {
                return;
            }
            if (cancel.is_cancelled ()) return;
            _recent.clear ();
            _artists.clear ();
            _recent_items.clear ();
            _artist_items.clear ();
            _hero_item = null;
            foreach (var it in recent) {
                if (it.kind != ItemKind.ALBUM) continue;
                if (_hero_item == null) {
                    _hero_item = it;
                    continue;
                }
                _recent_items.add (it);
                show_art (_recent.append_tile ("singularity-music-album", it.title, it.artist), it);
            }
            foreach (var it in artists) {
                if (it.kind != ItemKind.ARTIST) continue;
                _artist_items.add (it);
                show_art (_artists.append_tile ("singularity-music-artist", it.title, it.subtitle), it);
            }
            _hero.visible = _hero_item != null;
            if (_hero_item != null) {
                _hero.title = _hero_item.title;
                _hero.subtitle = _hero_item.artist;
                _hero.art.paintable = null;
                show_art (_hero.art, _hero_item);
            }
            _recent.visible = _recent_items.size > 0;
            _artists.visible = _artist_items.size > 0;
        }

        private static void show_art (MediaArt art, MediaItem it) {
            if (it.image_url == "") return;
            var cached = Artwork.get_default ().cached (it.image_url);
            if (cached != null) {
                art.paintable = cached;
                return;
            }
            Artwork.get_default ().load.begin (it.image_url, null, (o, r) => {
                var tex = Artwork.get_default ().load.end (r);
                if (tex != null) art.paintable = tex;
            });
        }

        private void play_album (MediaItem? album, bool shuffle) {
            var b = _source as Browsable;
            if (album == null || b == null) return;
            b.browse.begin (album.id, null, null, (o, r) => {
                try {
                    var page = b.browse.end (r);
                    var tracks = new Gee.ArrayList<MediaItem> ();
                    foreach (var it in page.items) if (it.playable && !it.kind.is_container ()) tracks.add (it);
                    if (tracks.size > 0) play_items (tracks, 0, shuffle);
                } catch (Error e) {
                    warning ("listen now: %s", e.message);
                }
            });
        }

        public void focus_start () {
            if (_hero.visible) _hero.focus_primary ();
        }
    }
}
