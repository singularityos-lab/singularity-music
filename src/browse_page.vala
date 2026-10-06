using Gtk;
using Singularity.Widgets;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class BrowseLevel : Object {
        public MediaSource source;
        public string? node;
        public string title;
        public string? query;
        public Gee.ArrayList<MediaItem> items = new Gee.ArrayList<MediaItem> ();
        public string? next_token = null;
        public int total = -1;
        public double scroll = 0;

        public BrowseLevel (MediaSource source, string? node, string title, string? query = null) {
            this.source = source;
            this.node = node;
            this.title = title;
            this.query = query;
        }
    }

    public class BrowsePage : Box {
        private Gee.ArrayList<BrowseLevel> _levels = new Gee.ArrayList<BrowseLevel> ();
        private Button _back;
        private Label _title;
        private Label _count;
        private Button _play_all;
        private Button _shuffle_all;
        private Button _external;
        private Box _actions;
        private Widget? _trailing = null;
        private Stack _stack;
        private ScrolledWindow _scroll;
        private Box _content;
        private ListBox? _list = null;
        private FlowBox? _grid = null;
        private StatusPage _status;
        private Button _status_action;
        private Cancellable? _cancel = null;
        private bool _loading_more = false;
        private uint _generation = 0;
        private string _status_uri = "";

        public signal void play_items (Gee.List<MediaItem> items, int start, bool shuffle);
        public signal void enqueue_items (Gee.List<MediaItem> items, bool next);
        public signal void open_uri (string uri);
        public signal void queue_remote (MediaItem item);
        public signal void level_changed ();

        public BrowsePage () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            hexpand = true;
            vexpand = true;
            add_css_class ("music-browse");

            var header = new Box (Orientation.HORIZONTAL, 8);
            header.add_css_class ("music-browse-header");
            header.margin_start = 24;
            header.margin_end = 160;
            header.margin_top = 18;
            header.margin_bottom = 6;
            _back = new Button.from_icon_name ("go-previous-symbolic");
            _back.add_css_class ("flat");
            _back.tooltip_text = _("Back");
            _back.valign = Align.CENTER;
            _back.clicked.connect (() => go_back ());
            header.append (_back);
            var titles = new Box (Orientation.VERTICAL, 2);
            titles.hexpand = true;
            titles.valign = Align.CENTER;
            _title = new Label ("");
            _title.add_css_class ("title-2");
            _title.xalign = 0;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _count = new Label ("");
            _count.add_css_class ("dim-label");
            _count.xalign = 0;
            titles.append (_title);
            titles.append (_count);
            header.append (titles);
            append (header);
            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.margin_start = 24;
            actions.margin_end = 24;
            actions.margin_bottom = 12;
            _actions = actions;
            _external = new Button.with_label ("");
            _external.valign = Align.CENTER;
            _external.add_css_class ("pill");
            _external.visible = false;
            _external.clicked.connect (() => {
                string? url = _external.get_data<string> ("url");
                if (url != null) open_uri (url);
            });
            _play_all = new Button ();
            var play_box = new Box (Orientation.HORIZONTAL, 6);
            play_box.append (new Image.from_icon_name ("media-playback-start-symbolic"));
            play_box.append (new Label (_("Play")));
            _play_all.set_child (play_box);
            _play_all.add_css_class ("suggested-action");
            _play_all.add_css_class ("pill");
            _play_all.clicked.connect (() => play_level (false));
            actions.append (_play_all);
            _shuffle_all = new Button ();
            var shuffle_box = new Box (Orientation.HORIZONTAL, 6);
            shuffle_box.append (new Image.from_icon_name ("media-playlist-shuffle-symbolic"));
            shuffle_box.append (new Label (_("Shuffle")));
            _shuffle_all.set_child (shuffle_box);
            _shuffle_all.add_css_class ("pill");
            _shuffle_all.clicked.connect (() => play_level (true));
            actions.append (_shuffle_all);
            actions.append (_external);
            append (actions);

            _stack = new Stack ();
            _stack.vexpand = true;
            _stack.transition_type = StackTransitionType.CROSSFADE;
            _stack.transition_duration = 150;

            _scroll = new ScrolledWindow ();
            _scroll.hscrollbar_policy = PolicyType.NEVER;
            _scroll.vexpand = true;
            _content = new Box (Orientation.VERTICAL, 0);
            _content.margin_start = 24;
            _content.margin_end = 24;
            _content.margin_bottom = 24;
            _scroll.set_child (_content);
            _scroll.edge_reached.connect ((pos) => {
                if (pos == PositionType.BOTTOM) load_more.begin ();
            });
            _stack.add_named (_scroll, "items");

            var spinner = new Spinner ();
            spinner.spinning = true;
            spinner.set_size_request (32, 32);
            spinner.halign = Align.CENTER;
            spinner.valign = Align.CENTER;
            _stack.add_named (spinner, "loading");

            _status = new StatusPage ();
            _status.vexpand = true;
            _status_action = new Button.with_label ("");
            _status_action.add_css_class ("pill");
            _status_action.halign = Align.CENTER;
            _status_action.clicked.connect (() => {
                if (_status_uri == "retry") reload ();
                else if (_status_uri != "") open_uri (_status_uri);
            });
            _status.child = _status_action;
            _stack.add_named (_status, "status");
            append (_stack);
            update_header ();
        }

        public BrowseLevel? current {
            owned get { return _levels.size > 0 ? _levels[_levels.size - 1] : null; }
        }

        public bool can_go_back {
            get { return _levels.size > 1; }
        }

        public void open_root (MediaSource source, string? node, string title) {
            _levels.clear ();
            push (new BrowseLevel (source, node, title));
        }

        public void open_search (MediaSource source, string query) {
            var base_level = _levels.size > 0 ? _levels[0] : null;
            _levels.clear ();
            if (base_level != null && base_level.query == null) _levels.add (base_level);
            push (new BrowseLevel (source, null, _("Results for “%s”").printf (query), query));
        }

        public void close_search () {
            if (current != null && current.query != null) go_back ();
        }

        private void push (BrowseLevel level) {
            if (current != null) current.scroll = _scroll.vadjustment.value;
            _levels.add (level);
            reload ();
        }

        public void go_back () {
            if (_levels.size <= 1) return;
            _levels.remove_at (_levels.size - 1);
            var level = current;
            double scroll = level.scroll;
            if (level.items.size > 0) {
                render ();
                Idle.add (() => {
                    _scroll.vadjustment.value = scroll;
                    return Source.REMOVE;
                });
            } else {
                reload ();
            }
            level_changed ();
        }

        public void reload () {
            var level = current;
            if (level == null) return;
            level.items.clear ();
            level.next_token = null;
            level.total = -1;
            if (_cancel != null) _cancel.cancel ();
            _cancel = new Cancellable ();
            _generation++;
            update_header ();
            _stack.visible_child_name = "loading";
            fetch.begin (level, null, _cancel, _generation);
            level_changed ();
        }

        public void refresh_if_showing (string source_id) {
            if (current != null && current.source.id == source_id) reload ();
        }

        private async MediaPage get_page (BrowseLevel level, string? token, Cancellable c) throws Error {
            if (level.query != null) {
                var s = level.source as Searchable;
                if (s == null) throw new MediaError.UNSUPPORTED (_("This source cannot search"));
                return yield s.search (level.query, MediaKind.AUDIO, token, c);
            }
            var b = level.source as Browsable;
            if (b == null) throw new MediaError.UNSUPPORTED (_("This source cannot be browsed"));
            return yield b.browse (level.node, token, c);
        }

        private async void fetch (BrowseLevel level, string? token, Cancellable c, uint generation) {
            try {
                var page = yield get_page (level, token, c);
                if (generation != _generation || level != current) return;
                if (token == null && page.title != "" && level.query == null && level.node != null) level.title = page.title;
                level.items.add_all (page.items);
                level.next_token = page.next_token;
                level.total = page.total;
                if (token == null && page.items.size == 0) {
                    if (page.action_uri != "" && page.action_label != "") {
                        show_welcome (color_icon (level.source.icon_name), level.title, page.notice, page.action_label, page.action_uri);
                    } else if (level.query != null) {
                        show_status ("edit-find", _("No Results"), _("Try other words."), "", "");
                    } else {
                        show_status (color_icon (level.source.icon_name), _("Nothing Here"), page.notice, "", "");
                    }
                    update_header ();
                    return;
                }
                if (token == null) render ();
                else append_items (page.items);
                update_header ();
            } catch (IOError.CANCELLED e) {
            } catch (Error e) {
                if (generation != _generation) return;
                if (token != null) return;
                string title = _("Could Not Load");
                if (e is MediaError.NEEDS_ACCOUNT || e is MediaError.AUTH_FAILED) {
                    show_welcome ("dialog-password", _("Sign-In Needed"), e.message, _("Online Accounts"), "settings:accounts");
                    return;
                }
                if (e is MediaError.RATE_LIMITED) title = _("Too Many Requests");
                if (e is MediaError.NOT_CONFIGURED) {
                    show_welcome ("applications-engineering", _("Setup Needed"), e.message, _("Settings"), "settings:app");
                    return;
                }
                show_status ("network-error", title, e.message, _("Try Again"), "retry");
            }
        }

        private static string color_icon (string name) {
            string base_name = name.has_suffix ("-symbolic") ? name.substring (0, name.length - 9) : name;
            var display = Gdk.Display.get_default ();
            if (display != null && Gtk.IconTheme.get_for_display (display).has_icon (base_name)) return base_name;
            return "folder-music";
        }

        private static string action_icon (string uri) {
            switch (uri) {
                case "settings:accounts": return "avatar-default";
                case "settings:app": return "applications-engineering";
                case "music:open-files": return "folder-open";
                default: return "web-browser";
            }
        }

        private static string action_text (string uri) {
            switch (uri) {
                case "settings:accounts": return _("Add or fix the account in Settings");
                case "settings:app": return _("Change the options of Music in Settings");
                case "music:open-files": return _("Add audio files or entire folders to the queue");
                default: return _("Opens in the browser");
            }
        }

        private void show_welcome (string icon, string title, string text, string action_label, string action_uri) {
            var old = _stack.get_child_by_name ("welcome");
            if (old != null) _stack.remove (old);
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.embedded = true;
            wp.compact = true;
            wp.app_icon_name = icon;
            wp.title = title;
            wp.subtitle = text;
            string uri = action_uri;
            wp.add_action (action_icon (uri), action_label, action_text (uri), () => {
                if (uri == "retry") reload ();
                else open_uri (uri);
            });
            _stack.add_named (wp, "welcome");
            _stack.visible_child_name = "welcome";
        }

        private void show_status (string icon, string title, string text, string action_label, string action_uri) {
            _status.icon_name = icon;
            _status.title = title;
            _status.description = text;
            _status_uri = action_uri;
            _status_action.label = action_label;
            _status_action.visible = action_label != "";
            _stack.visible_child_name = "status";
        }

        private async void load_more () {
            var level = current;
            if (level == null || _loading_more || level.next_token == null || _cancel == null) return;
            _loading_more = true;
            yield fetch (level, level.next_token, _cancel, _generation);
            _loading_more = false;
        }

        private static bool grid_kind (MediaItem it) {
            return it.kind == ItemKind.ALBUM || it.kind == ItemKind.PLAYLIST || it.kind == ItemKind.STATION;
        }

        private bool use_grid (Gee.List<MediaItem> items) {
            int grid = 0;
            foreach (var it in items) if (grid_kind (it)) grid++;
            return items.size > 0 && grid * 2 > items.size;
        }

        private void clear_content () {
            Widget? c;
            while ((c = _content.get_first_child ()) != null) _content.remove (c);
            _list = null;
            _grid = null;
        }

        private void render () {
            clear_content ();
            var level = current;
            if (use_grid (level.items)) {
                _grid = new FlowBox ();
                _grid.selection_mode = SelectionMode.NONE;
                _grid.homogeneous = true;
                _grid.min_children_per_line = 2;
                _grid.max_children_per_line = 8;
                _grid.column_spacing = 12;
                _grid.row_spacing = 12;
                _grid.activate_on_single_click = true;
                _grid.child_activated.connect ((child) => activate_item (child.get_data<MediaItem> ("item")));
                _grid.add_css_class ("music-grid");
                _content.append (_grid);
            } else {
                _list = new ListBox ();
                _list.selection_mode = SelectionMode.NONE;
                _list.add_css_class ("boxed-list");
                _list.row_activated.connect ((row) => activate_item (row.get_data<MediaItem> ("item")));
                _content.append (_list);
            }
            append_items (level.items);
            _stack.visible_child_name = "items";
            _scroll.vadjustment.value = 0;
        }

        private void append_items (Gee.List<MediaItem> items) {
            foreach (var it in items) {
                if (_grid != null) _grid.append (make_tile (it));
                else if (_list != null) _list.append (make_row (it));
            }
        }

        private Stack make_cover (MediaItem it, int size) {
            var stack = new Stack ();
            stack.add_css_class ("music-cover");
            stack.overflow = Overflow.HIDDEN;
            stack.set_size_request (size, size);
            stack.halign = Align.CENTER;
            stack.valign = Align.CENTER;
            var icon = new Image.from_icon_name (icon_for (it));
            icon.pixel_size = size >= 96 ? 64 : 32;
            stack.add_named (icon, "icon");
            var pic = new Image ();
            pic.pixel_size = size;
            stack.add_named (pic, "art");
            stack.visible_child_name = "icon";
            if (it.image_url != "") {
                var cached = Artwork.get_default ().cached (it.image_url);
                if (cached != null) {
                    pic.paintable = cached;
                    stack.visible_child_name = "art";
                } else {
                    Artwork.get_default ().load.begin (it.image_url, null, (o, r) => {
                        var tex = Artwork.get_default ().load.end (r);
                        if (tex == null) return;
                        pic.paintable = tex;
                        stack.visible_child_name = "art";
                    });
                }
            }
            return stack;
        }

        private static string icon_for (MediaItem it) {
            string? own = it.get_extra ("icon");
            if (own != null && own != "") return own;
            switch (it.kind) {
                case ItemKind.ALBUM: return "singularity-music-album";
                case ItemKind.ARTIST: return "singularity-music-artist";
                case ItemKind.PLAYLIST: return "singularity-music-playlist";
                case ItemKind.FOLDER: return "folder-music";
                case ItemKind.GENRE: return "folder-music";
                case ItemKind.STATION: return "audio-x-generic";
                default: return "audio-x-generic";
            }
        }

        private Widget make_tile (MediaItem it) {
            var child = new FlowBoxChild ();
            child.set_data<MediaItem> ("item", it);
            child.add_css_class ("music-tile");
            var box = new Box (Orientation.VERTICAL, 4);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 8;
            box.margin_end = 8;
            box.halign = Align.CENTER;
            box.width_request = 148;
            var cover = make_cover (it, 148);
            box.append (cover);
            var title = new Label (it.title);
            title.ellipsize = Pango.EllipsizeMode.END;
            title.max_width_chars = 18;
            title.xalign = 0;
            title.margin_top = 4;
            title.add_css_class ("heading");
            box.append (title);
            var sub = new Label (it.subtitle);
            sub.ellipsize = Pango.EllipsizeMode.END;
            sub.max_width_chars = 18;
            sub.xalign = 0;
            sub.add_css_class ("dim-label");
            sub.add_css_class ("caption");
            box.append (sub);
            child.set_child (box);
            child.tooltip_text = it.subtitle != "" ? "%s\n%s".printf (it.title, it.subtitle) : it.title;
            attach_menu (child, it);
            return child;
        }

        private Widget make_row (MediaItem it) {
            var row = new ListBoxRow ();
            row.set_data<MediaItem> ("item", it);
            row.activatable = it.browsable || it.playable;
            var h = new Box (Orientation.HORIZONTAL, 12);
            h.margin_start = 12;
            h.margin_end = 12;
            h.margin_top = 6;
            h.margin_bottom = 6;
            if ((it.kind == ItemKind.FOLDER || it.get_extra ("icon") != null) && it.image_url == "") {
                var icon = new Image.from_icon_name (icon_for (it));
                icon.pixel_size = 32;
                h.append (icon);
            } else {
                h.append (make_cover (it, 40));
            }
            var labels = new Box (Orientation.VERTICAL, 2);
            labels.hexpand = true;
            labels.valign = Align.CENTER;
            var title = new Label (it.title);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            labels.append (title);
            string sub = it.subtitle;
            if (it.kind == ItemKind.TRACK && it.album != "" && it.artist != "") sub = "%s, %s".printf (it.artist, it.album);
            if (sub != "") {
                var s = new Label (sub);
                s.xalign = 0;
                s.ellipsize = Pango.EllipsizeMode.END;
                s.add_css_class ("dim-label");
                s.add_css_class ("caption");
                labels.append (s);
            }
            h.append (labels);
            if (it.duration_ms > 0) {
                var d = new Label (it.display_duration ());
                d.add_css_class ("dim-label");
                d.add_css_class ("numeric");
                h.append (d);
            }
            if (it.external_url != "" && it.attribution != "") {
                var ext = new Button.from_icon_name ("external-link-symbolic");
                ext.add_css_class ("flat");
                ext.valign = Align.CENTER;
                ext.tooltip_text = it.external_label != "" ? it.external_label : _("Open in %s").printf (it.attribution);
                string url = it.external_url;
                ext.clicked.connect (() => open_uri (url));
                h.append (ext);
            }
            if (it.browsable) {
                var chevron = new Image.from_icon_name ("go-next-symbolic");
                chevron.add_css_class ("dim-label");
                h.append (chevron);
            }
            row.set_child (h);
            attach_menu (row, it);
            return row;
        }

        private void attach_menu (Widget w, MediaItem it) {
            var click = new GestureClick ();
            click.button = Gdk.BUTTON_SECONDARY;
            click.pressed.connect ((n, x, y) => {
                var menu = new ContextMenu (w);
                Gdk.Rectangle rect = { (int) x, (int) y, 1, 1 };
                menu.set_pointing_to (rect);
                bool isolated = (current.source.features & SourceFeatures.ISOLATED) != 0;
                if (it.playable) {
                    menu.add_item (_("Play"), "media-playback-start-symbolic", () => activate_item (it));
                    if (!isolated) {
                        menu.add_item (_("Play Next"), "go-next-symbolic", () => enqueue_one (it, true));
                        menu.add_item (_("Add to Queue"), "list-add-symbolic", () => enqueue_one (it, false));
                    } else {
                        menu.add_item (_("Add to Queue on %s").printf (current.source.title), "list-add-symbolic", () => queue_remote (it));
                    }
                }
                if (it.browsable) menu.add_item (_("Open"), "go-next-symbolic", () => activate_item (it));
                if (it.external_url != "") {
                    if (it.playable || it.browsable) menu.add_separator ();
                    menu.add_item (it.external_label != "" ? it.external_label : _("Open in Browser"), "external-link-symbolic", () => open_uri (it.external_url));
                }
                menu.popup ();
            });
            w.add_controller (click);
        }

        private void enqueue_one (MediaItem it, bool next) {
            var list = new Gee.ArrayList<MediaItem> ();
            list.add (it);
            enqueue_items (list, next);
        }

        private void activate_item (MediaItem? it) {
            if (it == null) return;
            if (it.browsable) {
                push (new BrowseLevel (current.source, it.id, it.title));
                level_changed ();
                return;
            }
            if (!it.playable) {
                if (it.external_url != "") open_uri (it.external_url);
                return;
            }
            var playable = new Gee.ArrayList<MediaItem> ();
            int start = 0;
            foreach (var x in current.items) {
                if (!x.playable) continue;
                if (x == it) start = playable.size;
                playable.add (x);
            }
            play_items (playable, start, false);
        }

        private void play_level (bool shuffle) {
            var level = current;
            if (level == null) return;
            var playable = new Gee.ArrayList<MediaItem> ();
            foreach (var x in level.items) if (x.playable) playable.add (x);
            if (playable.size > 0) {
                play_items (playable, shuffle ? Random.int_range (0, playable.size) : 0, shuffle);
                return;
            }
            collect_and_play.begin (level, shuffle);
        }

        private async void collect_and_play (BrowseLevel level, bool shuffle) {
            var b = level.source as Browsable;
            if (b == null) return;
            var all = new Gee.ArrayList<MediaItem> ();
            foreach (var container in level.items) {
                if (!container.browsable || all.size > 2000) continue;
                string? token = null;
                int pages = 0;
                do {
                    try {
                        var page = yield b.browse (container.id, token, _cancel);
                        foreach (var x in page.items) if (x.playable) all.add (x);
                        token = page.next_token;
                    } catch (Error e) {
                        token = null;
                    }
                    pages++;
                } while (token != null && pages < 20);
            }
            if (all.size > 0) play_items (all, shuffle ? Random.int_range (0, all.size) : 0, shuffle);
        }

        private void update_header () {
            var level = current;
            _back.visible = can_go_back;
            if (level == null) {
                _title.label = "";
                _count.label = "";
                _play_all.visible = false;
                _shuffle_all.visible = false;
                _external.visible = false;
                _actions.visible = false;
                return;
            }
            _title.label = level.title;
            int n = level.total >= 0 ? level.total : level.items.size;
            int playable = 0;
            int containers = 0;
            foreach (var x in level.items) {
                if (x.playable) playable++;
                if (x.browsable) containers++;
            }
            if (n <= 0) _count.label = "";
            else if (playable == level.items.size) _count.label = ngettext ("%d song", "%d songs", n).printf (n);
            else _count.label = ngettext ("%d item", "%d items", n).printf (n);
            _count.visible = _count.label != "";
            bool can_play = playable > 0 || (containers > 0 && level.node != null && (level.items.size == 0 || level.items[0].kind != ItemKind.FOLDER));
            _play_all.visible = can_play;
            _shuffle_all.visible = can_play;
            _external.visible = false;
            _actions.visible = can_play || _trailing != null;
            _play_all.visible = can_play;
        }

        public void set_trailing (Widget widget) {
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            _actions.append (spacer);
            _actions.append (widget);
            _trailing = widget;
            _actions.visible = true;
        }

        public void set_header_link (string? url, string label) {
            _external.visible = url != null && url != "";
            if (_external.visible) _actions.visible = true;
            _external.label = label;
            _external.set_data<string> ("url", url);
        }
    }
}
