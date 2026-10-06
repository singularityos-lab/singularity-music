using Gtk;
using GLib;
using Singularity;

namespace SingularityMusicWidget {

    public class NowPlayingProvider : Object, OverviewWidgetProvider {
        public string id           { get { return "music.now-playing"; } }
        public string provider_id  { get { return "dev.sinty.music"; } }
        public string display_name { get { return _("Now Playing"); } }
        public string icon_name    { get { return "audio-x-generic-symbolic"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[4];
                    _sizes[0] = WidgetSize(1, 1);
                    _sizes[1] = WidgetSize(1, 2);
                    _sizes[2] = WidgetSize(2, 1);
                    _sizes[3] = WidgetSize(2, 2);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance(string instance_id, WidgetSize size, Variant? config) {
            return new NowPlayingView(size);
        }
    }

    public class PlayerState : Object {
        public string bus_name = "";
        public string owner = "";
        public string identity = "";
        public string desktop_entry = "";
        public bool can_raise = false;
        public string status = "Stopped";
        public string title = "";
        public string artist = "";
        public string album = "";
        public string art_url = "";
        public int64 length = 0;
        public bool can_next = false;
        public bool can_previous = false;
        public int64 last_playing = 0;
    }

    public class NowPlayingSource : Object {
        private static NowPlayingSource? instance = null;
        public static NowPlayingSource get_default() {
            if (instance == null) instance = new NowPlayingSource();
            return instance;
        }

        public signal void changed();

        private DBusConnection? bus = null;
        private Gee.HashMap<string, PlayerState> players = new Gee.HashMap<string, PlayerState>();
        private string? pinned = null;

        private NowPlayingSource() {
            setup.begin();
        }

        private async void setup() {
            try {
                bus = yield Bus.get(BusType.SESSION, null);
            } catch (Error e) {
                warning("now playing: %s", e.message);
                return;
            }
            bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                "/org/freedesktop/DBus", null, DBusSignalFlags.NONE, (c, s, p, i, n, pars) => {
                    string name = pars.get_child_value(0).get_string();
                    string owner = pars.get_child_value(2).get_string();
                    if (!name.has_prefix("org.mpris.MediaPlayer2.")) return;
                    if (owner == "") {
                        players.unset(name);
                        if (pinned == name) pinned = null;
                        changed();
                    } else {
                        add_player.begin(name, owner);
                    }
                });
            bus.signal_subscribe(null, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                "/org/mpris/MediaPlayer2", null, DBusSignalFlags.NONE, (c, sender, p, i, n, pars) => {
                    foreach (var st in players.values) {
                        if (st.owner == sender) {
                            refresh_player.begin(st);
                            return;
                        }
                    }
                });
            try {
                var names = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "ListNames", null, new VariantType("(as)"),
                    DBusCallFlags.NONE, 1000, null);
                foreach (string name in names.get_child_value(0).get_strv()) {
                    if (!name.has_prefix("org.mpris.MediaPlayer2.")) continue;
                    try {
                        var o = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                            "org.freedesktop.DBus", "GetNameOwner", new Variant("(s)", name),
                            new VariantType("(s)"), DBusCallFlags.NONE, 500, null);
                        yield add_player(name, o.get_child_value(0).get_string());
                    } catch (Error e) {}
                }
            } catch (Error e) {}
        }

        private async void add_player(string name, string owner) {
            var st = new PlayerState();
            st.bus_name = name;
            st.owner = owner;
            st.identity = name.substring("org.mpris.MediaPlayer2.".length);
            players[name] = st;
            try {
                var all = yield bus.call(name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties",
                    "GetAll", new Variant("(s)", "org.mpris.MediaPlayer2"), new VariantType("(a{sv})"),
                    DBusCallFlags.NONE, 1000, null);
                var props = all.get_child_value(0);
                var v = props.lookup_value("Identity", VariantType.STRING);
                if (v != null && v.get_string() != "") st.identity = v.get_string();
                v = props.lookup_value("DesktopEntry", VariantType.STRING);
                if (v != null) st.desktop_entry = v.get_string();
                v = props.lookup_value("CanRaise", VariantType.BOOLEAN);
                if (v != null) st.can_raise = v.get_boolean();
            } catch (Error e) {}
            var info = app_info(st);
            if (info != null) st.identity = info.get_display_name();
            yield refresh_player(st);
        }

        private async void refresh_player(PlayerState st) {
            try {
                var all = yield bus.call(st.bus_name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties",
                    "GetAll", new Variant("(s)", "org.mpris.MediaPlayer2.Player"), new VariantType("(a{sv})"),
                    DBusCallFlags.NONE, 1000, null);
                var props = all.get_child_value(0);
                var v = props.lookup_value("PlaybackStatus", VariantType.STRING);
                st.status = v != null ? v.get_string() : "Stopped";
                if (st.status == "Playing") st.last_playing = get_monotonic_time();
                v = props.lookup_value("CanGoNext", VariantType.BOOLEAN);
                st.can_next = v != null && v.get_boolean();
                v = props.lookup_value("CanGoPrevious", VariantType.BOOLEAN);
                st.can_previous = v != null && v.get_boolean();
                st.title = "";
                st.artist = "";
                st.album = "";
                st.art_url = "";
                st.length = 0;
                var meta = props.lookup_value("Metadata", null);
                if (meta != null) {
                    var t = meta.lookup_value("xesam:title", VariantType.STRING);
                    if (t != null) st.title = t.get_string();
                    var a = meta.lookup_value("xesam:artist", null);
                    if (a != null && a.is_of_type(VariantType.STRING_ARRAY)) st.artist = string.joinv(", ", a.get_strv());
                    else if (a != null && a.is_of_type(VariantType.STRING)) st.artist = a.get_string();
                    var al = meta.lookup_value("xesam:album", VariantType.STRING);
                    if (al != null) st.album = al.get_string();
                    var art = meta.lookup_value("mpris:artUrl", VariantType.STRING);
                    if (art != null) st.art_url = art.get_string();
                    var len = meta.lookup_value("mpris:length", null);
                    if (len != null && len.is_of_type(VariantType.INT64)) st.length = len.get_int64();
                    else if (len != null && len.is_of_type(VariantType.UINT64)) st.length = (int64) len.get_uint64();
                }
                if (st.title == "" && meta != null) {
                    var u = meta.lookup_value("xesam:url", VariantType.STRING);
                    if (u != null) st.title = Path.get_basename(Uri.unescape_string(u.get_string()) ?? u.get_string());
                }
            } catch (Error e) {}
            changed();
        }

        public PlayerState? current() {
            if (pinned != null && players.has_key(pinned)) return players[pinned];
            PlayerState? best = null;
            foreach (var st in players.values) {
                if (best == null) { best = st; continue; }
                bool a = st.status == "Playing";
                bool b = best.status == "Playing";
                if (a != b) { if (a) best = st; continue; }
                if (st.last_playing > best.last_playing) best = st;
            }
            return best;
        }

        public PlayerState[] list() {
            PlayerState[] r = {};
            foreach (var st in players.values) r += st;
            return r;
        }

        public void pin(string name) {
            pinned = name;
            changed();
        }

        public void command(PlayerState st, string method) {
            if (bus == null) return;
            bus.call.begin(st.bus_name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player",
                method, null, null, DBusCallFlags.NONE, 1000, null);
        }

        public async int64 position(PlayerState st) {
            if (bus == null) return 0;
            try {
                var r = yield bus.call(st.bus_name, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties",
                    "Get", new Variant("(ss)", "org.mpris.MediaPlayer2.Player", "Position"),
                    new VariantType("(v)"), DBusCallFlags.NONE, 500, null);
                var v = r.get_child_value(0).get_variant();
                if (v.is_of_type(VariantType.INT64)) return v.get_int64();
            } catch (Error e) {}
            return 0;
        }

        public DesktopAppInfo? app_info(PlayerState st) {
            if (st.desktop_entry == "") return null;
            string id = st.desktop_entry.has_suffix(".desktop") ? st.desktop_entry : st.desktop_entry + ".desktop";
            return new DesktopAppInfo(id);
        }

        public void raise(PlayerState st) {
            if (st.can_raise && bus != null) {
                bus.call.begin(st.bus_name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2",
                    "Raise", null, null, DBusCallFlags.NONE, 1000, null);
                return;
            }
            var info = app_info(st);
            if (info == null) return;
            try {
                info.launch(null, null);
            } catch (Error e) {
                warning("now playing: %s", e.message);
            }
        }
    }

    public class NowPlayingView : Gtk.Box {
        private WidgetSize size;
        private NowPlayingSource source;
        private ulong handler = 0;
        private uint tick_id = 0;
        private string loaded_art = "";
        private Cancellable? art_cancel = null;

        private Gtk.Stack stack;
        private Gtk.Picture cover;
        private Gtk.Image cover_icon;
        private Gtk.Stack cover_stack;
        private Gtk.Image app_icon;
        private Gtk.Label app_label;
        private Gtk.MenuButton players_btn;
        private Gtk.Label title_label;
        private Gtk.Label artist_label;
        private Gtk.Button prev_btn;
        private Gtk.Button play_btn;
        private Gtk.Button next_btn;
        private Gtk.ProgressBar progress;

        public NowPlayingView(WidgetSize size) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.size = size;
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;
            add_css_class("media-player-card");
            source = NowPlayingSource.get_default();

            stack = new Gtk.Stack();
            stack.hexpand = true;
            stack.vexpand = true;
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.add_named(build_empty(), "empty");
            stack.add_named(build_player(), "player");
            append(stack);

            handler = source.changed.connect(update);
            update();
            destroy.connect(() => {
                if (handler != 0) { source.disconnect(handler); handler = 0; }
                if (tick_id != 0) { Source.remove(tick_id); tick_id = 0; }
                if (art_cancel != null) art_cancel.cancel();
            });
        }

        private bool compact { get { return size.w == 1 && size.h == 1; } }

        private Gtk.Widget build_empty() {
            var box = new Gtk.Box(Orientation.VERTICAL, 8);
            box.halign = Align.CENTER;
            box.valign = Align.CENTER;
            var icon = new Gtk.Image.from_icon_name("dev.sinty.music");
            icon.pixel_size = compact ? 48 : 56;
            box.append(icon);
            if (!compact) {
                var label = new Gtk.Label(_("Nothing playing"));
                label.add_css_class("heading");
                box.append(label);
                var open = new Gtk.Button.with_label(_("Open Music"));
                open.add_css_class("suggested-action");
                open.halign = Align.CENTER;
                open.clicked.connect(open_music);
                box.append(open);
            } else {
                icon.tooltip_text = _("Nothing playing");
                var click = new GestureClick();
                click.released.connect(() => open_music());
                box.add_controller(click);
            }
            return box;
        }

        private void open_music() {
            var info = new DesktopAppInfo("dev.sinty.music.desktop");
            if (info == null) return;
            try {
                info.launch(null, null);
            } catch (Error e) {
                warning("now playing: %s", e.message);
            }
        }

        private Gtk.Widget build_player() {
            cover = new Gtk.Picture();
            cover.content_fit = ContentFit.COVER;
            cover.can_shrink = true;
            cover.add_css_class("overview-photo");
            cover.overflow = Overflow.HIDDEN;
            cover_icon = new Gtk.Image();
            cover_icon.pixel_size = 64;
            cover_stack = new Gtk.Stack();
            cover_stack.add_named(cover_icon, "icon");
            cover_stack.add_named(cover, "art");
            cover_stack.hexpand = true;
            cover_stack.vexpand = true;
            cover_stack.tooltip_text = _("Show the player");
            cover_stack.cursor = new Gdk.Cursor.from_name("pointer", null);
            var click = new GestureClick();
            click.released.connect(() => {
                var st = source.current();
                if (st != null) source.raise(st);
            });
            cover_stack.add_controller(click);

            app_icon = new Gtk.Image();
            app_icon.pixel_size = 16;
            app_label = new Gtk.Label("");
            app_label.add_css_class("caption");
            app_label.add_css_class("dim-label");
            app_label.xalign = 0;
            app_label.hexpand = true;
            app_label.ellipsize = Pango.EllipsizeMode.END;
            players_btn = new Gtk.MenuButton();
            players_btn.icon_name = "view-more-horizontal-symbolic";
            players_btn.add_css_class("flat");
            players_btn.tooltip_text = _("Choose a player");
            players_btn.visible = false;
            var header = new Gtk.Box(Orientation.HORIZONTAL, 6);
            header.append(app_icon);
            header.append(app_label);
            header.append(players_btn);

            title_label = new Gtk.Label("");
            title_label.add_css_class("heading");
            title_label.ellipsize = Pango.EllipsizeMode.END;
            title_label.xalign = 0;
            artist_label = new Gtk.Label("");
            artist_label.add_css_class("caption");
            artist_label.add_css_class("dim-label");
            artist_label.ellipsize = Pango.EllipsizeMode.END;
            artist_label.xalign = 0;
            var text = new Gtk.Box(Orientation.VERTICAL, 2);
            text.append(title_label);
            text.append(artist_label);

            prev_btn = control("media-skip-backward-symbolic", _("Previous"), "Previous");
            play_btn = control("media-playback-start-symbolic", _("Play"), "PlayPause");
            play_btn.remove_css_class("flat");
            play_btn.add_css_class("circular-button");
            next_btn = control("media-skip-forward-symbolic", _("Next"), "Next");
            progress = new Gtk.ProgressBar();
            progress.hexpand = true;

            if (compact) {
                var overlay = new Gtk.Overlay();
                overlay.set_child(cover_stack);
                play_btn.halign = Align.END;
                play_btn.valign = Align.END;
                play_btn.margin_end = 8;
                play_btn.margin_bottom = 8;
                overlay.add_overlay(play_btn);
                return overlay;
            }

            var controls = new Gtk.Box(Orientation.HORIZONTAL, 4);
            controls.halign = Align.CENTER;
            controls.valign = Align.CENTER;
            controls.append(prev_btn);
            controls.append(play_btn);
            controls.append(next_btn);

            var box = new Gtk.Box(Orientation.VERTICAL, 8);
            box.margin_start = 14;
            box.margin_end = 14;
            box.margin_top = 12;
            box.margin_bottom = 12;
            if (size.w >= 2 && size.h == 1) {
                header.visible = false;
                cover_stack.hexpand = false;
                cover_stack.set_size_request(76, 76);
                cover_stack.valign = Align.CENTER;
                var right = new Gtk.Box(Orientation.VERTICAL, 6);
                right.hexpand = true;
                right.valign = Align.CENTER;
                right.append(text);
                controls.halign = Align.START;
                right.append(controls);
                var row = new Gtk.Box(Orientation.HORIZONTAL, 12);
                row.vexpand = true;
                row.append(cover_stack);
                row.append(right);
                box.append(row);
                return box;
            }
            box.append(header);
            box.append(cover_stack);
            box.append(text);
            if (size.h >= 2 && size.w >= 2) box.append(progress);
            box.append(controls);
            return box;
        }

        private Gtk.Button control(string icon, string tooltip, string method) {
            var b = new Gtk.Button.from_icon_name(icon);
            b.add_css_class("flat");
            b.tooltip_text = tooltip;
            b.valign = Align.CENTER;
            b.clicked.connect(() => {
                var st = source.current();
                if (st != null) source.command(st, method);
            });
            return b;
        }

        private void update() {
            var st = source.current();
            if (st == null) {
                stack.visible_child_name = "empty";
                stop_tick();
                return;
            }
            stack.visible_child_name = "player";
            title_label.label = st.title != "" ? st.title : st.identity;
            artist_label.label = st.artist != "" ? st.artist : st.album;
            artist_label.visible = artist_label.label != "";
            app_label.label = st.identity;
            var info = source.app_info(st);
            GLib.Icon? gicon = info != null ? info.get_icon() : null;
            if (gicon != null) {
                app_icon.gicon = gicon;
                cover_icon.gicon = gicon;
            } else {
                app_icon.icon_name = "audio-x-generic-symbolic";
                cover_icon.icon_name = "dev.sinty.music";
            }
            bool playing = st.status == "Playing";
            play_btn.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            play_btn.tooltip_text = playing ? _("Pause") : _("Play");
            prev_btn.sensitive = st.can_previous;
            next_btn.sensitive = st.can_next;
            cover_stack.tooltip_text = _("Show %s").printf(st.identity);
            update_players();
            load_art(st.art_url);
            if (playing && progress.get_parent() != null) start_tick(); else stop_tick();
            tick();
        }

        private void update_players() {
            var all = source.list();
            players_btn.visible = all.length > 1;
            if (all.length < 2) return;
            var list = new Gtk.Box(Orientation.VERTICAL, 2);
            var pop = new Gtk.Popover();
            foreach (var p in all) {
                var b = new Gtk.Button.with_label(p.identity);
                b.add_css_class("flat");
                string name = p.bus_name;
                b.clicked.connect(() => {
                    pop.popdown();
                    source.pin(name);
                });
                list.append(b);
            }
            pop.child = list;
            players_btn.popover = pop;
        }

        private void start_tick() {
            if (tick_id != 0) return;
            tick_id = Timeout.add_seconds(1, () => { tick(); return Source.CONTINUE; });
        }

        private void stop_tick() {
            if (tick_id != 0) { Source.remove(tick_id); tick_id = 0; }
        }

        private void tick() {
            var st = source.current();
            if (st == null || st.length <= 0 || progress.get_parent() == null) {
                progress.visible = false;
                return;
            }
            progress.visible = true;
            source.position.begin(st, (o, r) => {
                int64 pos = source.position.end(r);
                progress.fraction = ((double) pos / (double) st.length).clamp(0.0, 1.0);
            });
        }

        private void load_art(string url) {
            if (url == loaded_art) return;
            loaded_art = url;
            if (art_cancel != null) art_cancel.cancel();
            if (url == "") {
                cover_stack.visible_child_name = "icon";
                return;
            }
            art_cancel = new Cancellable();
            var cancel = art_cancel;
            if (url.has_prefix("http://") || url.has_prefix("https://")) {
                var session = new Soup.Session();
                session.timeout = 10;
                var msg = new Soup.Message("GET", url);
                session.send_and_read_async.begin(msg, Priority.DEFAULT, cancel, (o, r) => {
                    try {
                        var bytes = session.send_and_read_async.end(r);
                        if (cancel.is_cancelled() || msg.status_code != 200) return;
                        cover.paintable = Gdk.Texture.from_bytes(bytes);
                        cover_stack.visible_child_name = "art";
                    } catch (Error e) {
                        if (!cancel.is_cancelled()) cover_stack.visible_child_name = "icon";
                    }
                });
                return;
            }
            var file = File.new_for_uri(url);
            file.load_bytes_async.begin(cancel, (o, r) => {
                try {
                    var bytes = file.load_bytes_async.end(r, null);
                    if (cancel.is_cancelled()) return;
                    cover.paintable = Gdk.Texture.from_bytes(bytes);
                    cover_stack.visible_child_name = "art";
                } catch (Error e) {
                    if (!cancel.is_cancelled()) cover_stack.visible_child_name = "icon";
                }
            });
        }
    }

    [CCode (cname = "singularity_music_widget_new")]
    public static Object singularity_music_widget_new() {
        return new NowPlayingProvider();
    }
}
