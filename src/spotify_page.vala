using Gtk;
using Singularity.Widgets;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class SpotifyPage : Box {
        public const string ID = "spotify-section";
        public const string DOWNLOAD_URL = "https://www.spotify.com/download/linux/";
        public const string DASHBOARD_URL = "https://developer.spotify.com/dashboard";
        public const string REDIRECT_URI = "http://127.0.0.1:43019/callback";

        private SpotifyBridge _bridge;
        private MediaHost _host;
        private MediaSource? _web = null;
        private RemotePlayer? _remote = null;
        private LocalReceiver? _receiver = null;
        private Stack _stack;
        private BrowsePage _library;
        private Button _devices_btn;
        private Label _devices_label;
        private Label _where;
        private EntryRow _client_row;
        private ActionRow _sign_in_row;
        private Button _sign_in_btn;
        private Label _setup_status;
        private PreferencesGroup _app_group;
        private ActionRow _app_row;
        private Button _app_play;
        private Button _app_open;
        private bool _client_configured = false;
        private string _flow = "";

        public signal void open_uri (string uri);
        public signal void play_remote (RemotePlayer remote, MediaItem item, MediaItem? context);

        public SpotifyPage (SpotifyBridge bridge, MediaHost host) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            _bridge = bridge;
            _host = host;
            add_css_class ("music-spotify");
            hexpand = true;
            vexpand = true;

            _stack = new Stack ();
            _stack.vexpand = true;
            _stack.transition_type = StackTransitionType.CROSSFADE;
            _stack.add_named (build_setup (), "setup");
            _stack.add_named (build_library (), "library");
            append (_stack);

            _bridge.changed.connect (() => sync_app ());
            map.connect (() => {
                _bridge.set_polling (true);
                if (_remote != null) _remote.set_active (true);
                refresh_client.begin ();
            });
            unmap.connect (() => {
                _bridge.set_polling (false);
                if (_remote != null) _remote.set_active (false);
            });
            var manager = Singularity.Accounts.Manager.get_default ();
            manager.sign_in_finished.connect ((flow, account, message) => {
                if (flow != _flow) return;
                _flow = "";
                _sign_in_btn.sensitive = true;
                if (message != "") show_setup_status (message);
                else show_setup_status (_("Signed in. Loading your library…"));
            });
            set_web_source (null);
            sync_app ();
        }

        private Widget build_setup () {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            var box = new Box (Orientation.VERTICAL, 0);
            box.halign = Align.CENTER;
            box.margin_bottom = 24;
            box.width_request = 560;

            var welcome = new WelcomePage ();
            welcome.is_section = true;
            welcome.embedded = true;
            welcome.compact = true;
            welcome.app_icon_name = "singularity-account-music-service";
            welcome.title = "Spotify";
            welcome.subtitle = _("Search Spotify, browse your library and choose what plays on your phone, your speakers or the Spotify app, all from Music.");
            welcome.add_action ("applications-engineering", _("Open the Spotify Developer Dashboard"),
                _("Spotify asks each person to connect with an app of their own; it is free and takes a minute"), () => open_uri (DASHBOARD_URL));
            box.append (welcome);

            var steps = new PreferencesGroup (_("Connect Your Spotify App"),
                _("On the dashboard create an app, choose Web API, and add the redirect URI below. Then copy its client ID here."));
            steps.margin_top = 12;
            var redirect = new ActionRow (_("Redirect URI"), REDIRECT_URI);
            var copy = new Button.from_icon_name ("edit-copy-symbolic");
            copy.add_css_class ("flat");
            copy.valign = Align.CENTER;
            copy.tooltip_text = _("Copy the Redirect URI");
            copy.clicked.connect (() => {
                get_clipboard ().set_text (REDIRECT_URI);
                show_setup_status (_("Redirect URI copied"));
            });
            redirect.add_suffix (copy);
            steps.add_row (redirect);
            _client_row = new EntryRow (_("Client ID"));
            var save = new Button.with_label (_("Save"));
            save.valign = Align.CENTER;
            save.clicked.connect (() => save_client.begin ());
            _client_row.add_suffix (save);
            _client_row.entry_activated.connect (() => save_client.begin ());
            steps.add_row (_client_row);
            _sign_in_row = new ActionRow (_("Sign In"), _("Spotify asks you to allow Music to see your library and control playback"));
            _sign_in_btn = new Button.with_label (_("Sign In"));
            _sign_in_btn.add_css_class ("suggested-action");
            _sign_in_btn.valign = Align.CENTER;
            _sign_in_btn.clicked.connect (() => sign_in.begin ());
            _sign_in_row.add_suffix (_sign_in_btn);
            steps.add_row (_sign_in_row);
            _setup_status = new Label ("");
            _setup_status.add_css_class ("dim-label");
            _setup_status.wrap = true;
            _setup_status.xalign = 0;
            _setup_status.margin_start = 12;
            _setup_status.margin_top = 6;
            _setup_status.margin_bottom = 6;
            _setup_status.visible = false;
            steps.add_row (_setup_status);
            box.append (steps);

            _app_group = new PreferencesGroup (_("Spotify App on This Computer"),
                _("Without a client ID, Music shows and controls what the Spotify app plays, also with a free account."));
            _app_group.margin_top = 12;
            _app_row = new ActionRow ("", null, "singularity-account-music-service");
            _app_play = new Button.from_icon_name ("media-playback-start-symbolic");
            _app_play.add_css_class ("flat");
            _app_play.valign = Align.CENTER;
            _app_play.tooltip_text = _("Play or Pause");
            _app_play.clicked.connect (() => _bridge.play_pause ());
            _app_row.add_suffix (_app_play);
            _app_open = new Button.with_label ("");
            _app_open.valign = Align.CENTER;
            _app_open.clicked.connect (() => {
                if (SpotifyBridge.app_info () != null || _bridge.running) _bridge.raise_or_launch (get_root () as Gtk.Window);
                else open_uri (DOWNLOAD_URL);
            });
            _app_row.add_suffix (_app_open);
            _app_group.add_row (_app_row);
            box.append (_app_group);

            scroll.set_child (box);
            return scroll;
        }

        private Widget build_library () {
            _library = new BrowsePage ();
            _library.play_items.connect ((items, start, shuffle) => start_remote.begin (items, start));
            _library.open_uri.connect ((uri) => open_uri (uri));
            _library.queue_remote.connect ((item) => add_to_queue.begin (item));
            var picker = new Box (Orientation.HORIZONTAL, 8);
            _where = new Label ("");
            _where.add_css_class ("dim-label");
            _where.ellipsize = Pango.EllipsizeMode.END;
            _where.max_width_chars = 40;
            _where.valign = Align.CENTER;
            picker.append (_where);
            _devices_btn = new Button ();
            _devices_btn.add_css_class ("pill");
            _devices_btn.valign = Align.CENTER;
            _devices_btn.tooltip_text = _("Choose the Spotify device that plays");
            var content = new Box (Orientation.HORIZONTAL, 6);
            content.append (new Image.from_icon_name ("audio-speakers-symbolic"));
            _devices_label = new Label (_("Choose a Device"));
            content.append (_devices_label);
            _devices_btn.set_child (content);
            _devices_btn.clicked.connect (() => show_devices.begin ());
            picker.append (_devices_btn);
            _library.set_trailing (picker);
            return _library;
        }

        private void show_setup_status (string text) {
            _setup_status.label = text;
            _setup_status.visible = text != "";
        }

        private async void refresh_client () {
            try {
                foreach (var p in yield Singularity.Accounts.Manager.get_default ().list_providers ()) {
                    if (p.id != "spotify") continue;
                    _client_configured = p.configured;
                    if (p.client_source == "user" && _client_row.text == "") _client_row.text = p.client_id;
                }
            } catch (Error e) {
                show_setup_status (_("Online Accounts is not available: %s").printf (e.message));
            }
            _sign_in_row.sensitive = _client_configured;
        }

        private async void save_client () {
            string id = _client_row.text.strip ();
            if (id == "") {
                show_setup_status (_("Enter the client ID of your Spotify app"));
                return;
            }
            try {
                yield Singularity.Accounts.Manager.get_default ().set_oauth_client ("spotify", id, "");
                show_setup_status (_("Client ID saved. Now sign in."));
            } catch (Error e) {
                show_setup_status (e.message);
            }
            yield refresh_client ();
        }

        private async void sign_in () {
            var manager = Singularity.Accounts.Manager.get_default ();
            _sign_in_btn.sensitive = false;
            show_setup_status (_("Waiting for Spotify…"));
            try {
                string url;
                _flow = yield manager.begin_sign_in ("spotify", new HashTable<string, Variant> (str_hash, str_equal), out url);
                bool shown = yield manager.open_sign_in_window (_flow, url, "Spotify", "singularity-account-music-service");
                if (!shown) _host.open_external (url);
            } catch (Error e) {
                _flow = "";
                _sign_in_btn.sensitive = true;
                show_setup_status (e.message);
            }
        }

        public void set_web_source (MediaSource? source) {
            if (source == _web && source != null) return;
            _web = source;
            if (source != null) {
                _library.open_root (source, null, "Spotify");
                _stack.visible_child_name = "library";
                attach_default_remote.begin ();
            } else {
                _stack.visible_child_name = "setup";
                refresh_client.begin ();
            }
        }

        public void set_receiver (LocalReceiver? receiver) {
            _receiver = receiver;
            sync_device ();
        }

        private async RemoteDevice? receiver_device (Gee.List<RemoteDevice>? known) {
            if (_receiver == null || !_receiver.running || _remote == null) return null;
            try {
                var list = known ?? yield _remote.devices (null);
                foreach (var d in list) if (d.name == _receiver.device_name) return d;
            } catch (Error e) {
            }
            return null;
        }

        public void search (string text) {
            if (_web == null) return;
            if (text == "") _library.close_search ();
            else _library.open_search (_web, text);
        }

        private void sync_app () {
            if (_bridge.running && _bridge.title != "") {
                _app_row.title = _bridge.title;
                _app_row.subtitle = _bridge.artist;
                _app_play.visible = true;
                _app_play.icon_name = _bridge.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
                _app_open.label = _("Show");
            } else if (_bridge.running) {
                _app_row.title = _("Nothing Playing");
                _app_row.subtitle = _("Start a song in Spotify to control it here and with the media keys");
                _app_play.visible = false;
                _app_open.label = _("Show");
            } else if (SpotifyBridge.app_info () != null || _bridge.installed) {
                _app_row.title = _("Spotify Is Closed");
                _app_row.subtitle = _("Open it to control it from Music");
                _app_play.visible = false;
                _app_open.label = _("Open");
            } else {
                _app_row.title = _("Spotify Is Not Installed");
                _app_row.subtitle = _("Available from Spotify as a snap or as a community Flatpak on Flathub");
                _app_play.visible = false;
                _app_open.label = _("Get Spotify");
            }
        }

        private async RemotePlayer? remote_for (MediaItem item) throws Error {
            var resolver = _web as PlaybackResolver;
            if (resolver == null) return null;
            var pb = yield resolver.resolve (item, null);
            if (pb.kind == PlaybackKind.EXTERNAL) {
                open_uri (pb.uri);
                return null;
            }
            return pb.remote;
        }

        private void attach_remote (RemotePlayer remote) {
            if (_remote == remote) return;
            _remote = remote;
            _remote.state_changed.connect (() => sync_device ());
            _remote.set_active (get_mapped ());
            sync_device ();
        }

        private async void attach_default_remote () {
            if (_web == null) return;
            try {
                var r = yield remote_for (new MediaItem (_web.id, "devices", ItemKind.TRACK, ""));
                if (r != null) attach_remote (r);
                yield pick_device (null);
            } catch (Error e) {
                debug ("music: spotify devices: %s", e.message);
            }
        }

        private void sync_device () {
            if (_devices_label == null) return;
            if (_receiver != null && !_receiver.installed) {
                _where.label = _("librespot is not installed");
                return;
            }
            var d = _remote != null ? _remote.device : null;
            if (d != null && d.name != "") {
                _devices_label.label = d.name;
                _where.label = _("Plays on");
            } else {
                _devices_label.label = _("Choose a Device");
                _where.label = "";
            }
        }

        private async void pick_device (Gee.List<RemoteDevice>? known) throws Error {
            if (_remote == null) return;
            var list = known ?? yield _remote.devices (null);
            foreach (var d in list) {
                if (d.active) {
                    _devices_label.label = d.name;
                    _where.label = _("Plays on");
                    return;
                }
            }
        }

        private async void start_remote (Gee.List<MediaItem> items, int start) {
            if (items.size == 0) return;
            var item = items[start.clamp (0, items.size - 1)];
            try {
                var r = yield remote_for (item);
                if (r == null) return;
                attach_remote (r);
                if (_receiver != null && _receiver.running) {
                    var mine = yield receiver_device (null);
                    if (mine != null && !mine.active) {
                        try {
                            yield r.transfer (mine.id, false);
                        } catch (Error e) {
                            _host.show_message ("spotify", e.message);
                        }
                    } else if (mine == null) {
                        _host.show_message ("spotify", _("%s is not ready yet, so Spotify plays on the device in use.").printf (_receiver.device_name));
                    }
                }
                var level = _library.current;
                MediaItem? context = null;
                if (level != null && level.node != null && level.query == null && (level.node.contains ("/playlist/") || level.node.contains ("/album/")))
                    context = new MediaItem (_web.id, level.node, ItemKind.PLAYLIST, level.title);
                play_remote (r, item, context);
            } catch (Error e) {
                _host.show_message ("spotify", e.message);
            }
        }

        private async void add_to_queue (MediaItem item) {
            try {
                var r = yield remote_for (item);
                var q = r as RemoteQueue;
                if (q == null) return;
                yield q.add_to_queue (item);
                _host.show_message ("spotify", _("Added to the Spotify queue"));
            } catch (Error e) {
                _host.show_message ("spotify", e.message);
            }
        }

        private Widget device_row (RemoteDevice d, Popover pop) {
            var b = new Button ();
            b.add_css_class ("flat");
            var row = new Box (Orientation.HORIZONTAL, 10);
            string icon = "audio-speakers-symbolic";
            if (d.device_type == "smartphone") icon = "phone-symbolic";
            else if (d.device_type == "computer") icon = "computer-symbolic";
            else if (d.device_type == "tv") icon = "video-display-symbolic";
            row.append (new Image.from_icon_name (icon));
            var name = new Label (d.name);
            name.xalign = 0;
            name.hexpand = true;
            row.append (name);
            if (d.active) row.append (new Image.from_icon_name ("object-select-symbolic"));
            b.set_child (row);
            b.sensitive = !d.restricted;
            string id = d.id;
            b.clicked.connect (() => {
                pop.popdown ();
                transfer.begin (id);
            });
            return b;
        }

        private async void transfer (string id) {
            try {
                yield _remote.transfer (id, _remote.state == PlaybackState.PLAYING);
                yield pick_device (null);
            } catch (Error e) {
                _host.show_message ("spotify", e.message);
            }
        }

        private async void show_devices () {
            if (_remote == null) yield attach_default_remote ();
            if (_remote == null) return;
            var pop = new Popover ();
            pop.set_parent (_devices_btn);
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_top = 6;
            box.margin_bottom = 6;
            box.margin_start = 6;
            box.margin_end = 6;
            box.width_request = 300;
            var title = new Label (_("Play On"));
            title.add_css_class ("heading");
            title.xalign = 0;
            title.margin_start = 8;
            box.append (title);
            string text = _("Spotify streams music only to its own apps and devices, so the sound comes from the device you choose here.");
            if (_receiver != null) text = _receiver.status_text;
            var note = new Label (text);
            note.add_css_class ("dim-label");
            note.add_css_class ("caption");
            note.wrap = true;
            note.xalign = 0;
            note.max_width_chars = 36;
            note.margin_start = 8;
            note.margin_end = 8;
            note.margin_bottom = 6;
            box.append (note);
            try {
                var list = yield _remote.devices (null);
                foreach (var d in list) box.append (device_row (d, pop));
                if (list.size == 0) {
                    var none = new Label (_("No devices. Open Spotify on your phone, a speaker or this computer."));
                    none.wrap = true;
                    none.max_width_chars = 36;
                    none.xalign = 0;
                    none.margin_start = 8;
                    box.append (none);
                }
                yield pick_device (list);
            } catch (Error e) {
                var err = new Label (e.message);
                err.wrap = true;
                err.max_width_chars = 36;
                box.append (err);
            }
            pop.set_child (box);
            pop.popup ();
        }
    }
}
