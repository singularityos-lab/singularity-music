using Gtk;
using GLib;

namespace Singularity.Apps.Music {

    public class MusicApp : Singularity.Application, Singularity.Migration.Migratable, Singularity.Startup.Bootable {

        private MusicWindow? _window = null;

        private LibrarySearch _search;

        public MusicApp () {
            Object (application_id: "dev.sinty.music",
                    flags: GLib.ApplicationFlags.HANDLES_OPEN);
            _search = new LibrarySearch (this);
            _search.export (this);
            add_main_option ("shuffle-all", 0, OptionFlags.NONE, OptionArg.NONE, _("Shuffle all the songs in the Music folder"), null);
            add_main_option ("open-files", 0, OptionFlags.NONE, OptionArg.NONE, _("Choose files to play"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            string? action = null;
            if (options.contains ("shuffle-all")) action = "shuffle-all";
            else if (options.contains ("open-files")) action = "open-files";
            if (action == null) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("music: %s", e.message);
                return 1;
            }
            activate_action (action, null);
            return get_is_remote () ? 0 : -1;
        }

        public MusicLibrary library { get { return _search.library; } }

        public MusicWindow ensure_window () {
            show_window ();
            return _window;
        }

        private void _shuffle_all () {
            hold ();
            _search.library.refresh.begin ((o, r) => {
                _search.library.refresh.end (r);
                string[] uris = {};
                foreach (var t in _search.library.all) uris += t.uri;
                for (int i = uris.length - 1; i > 0; i--) {
                    int j = GLib.Random.int_range (0, i + 1);
                    string tmp = uris[i];
                    uris[i] = uris[j];
                    uris[j] = tmp;
                }
                if (uris.length > 0) play_uris (uris, true);
                else show_window ();
                release ();
            });
        }

        protected override void startup () {
            base.startup ();
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Open Files…"), "win.open");
            file.append_section (null, f1);
            var f_share = new GLib.Menu ();
            f_share.append (_("Share…"), "win.share");
            file.append_section (null, f_share);
            var f2 = new GLib.Menu ();
            f2.append (_("Close Window"), "win.close");
            f2.append (_("Quit"), "app.quit");
            file.append_section (null, f2);
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Clear Queue"), "win.clear-playlist");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Settings"), "app.settings");
            edit.append_section (null, e2);
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("Library"), "win.library");
            v1.append (_("Now Playing"), "win.now-playing");
            v1.append (_("Lyrics"), "win.lyrics");
            view.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Queue"), "win.playlist");
            v2.append (_("Mini Player"), "win.mini-player");
            view.append_section (null, v2);
            var v3 = new GLib.Menu ();
            v3.append (_("Search"), "win.find");
            view.append_section (null, v3);
            menu.append_submenu (_("View"), view);
            var playback = new GLib.Menu ();
            var p1 = new GLib.Menu ();
            p1.append (_("Play or Pause"), "win.play-pause");
            p1.append (_("Stop"), "win.stop");
            playback.append_section (null, p1);
            var p2 = new GLib.Menu ();
            p2.append (_("Previous"), "win.previous");
            p2.append (_("Next"), "win.next");
            p2.append (_("Skip Back 10 Seconds"), "win.skip-back");
            p2.append (_("Skip Forward 10 Seconds"), "win.skip-forward");
            playback.append_section (null, p2);
            var p3 = new GLib.Menu ();
            p3.append (_("Shuffle"), "win.shuffle");
            var repeat = new GLib.Menu ();
            repeat.append (_("Off"), "win.repeat::none");
            repeat.append (_("Repeat All"), "win.repeat::all");
            repeat.append (_("Repeat One"), "win.repeat::one");
            p3.append_submenu (_("Repeat"), repeat);
            playback.append_section (null, p3);
            var p4 = new GLib.Menu ();
            p4.append (_("Volume Up"), "win.volume-up");
            p4.append (_("Volume Down"), "win.volume-down");
            p4.append (_("Mute"), "win.mute");
            playback.append_section (null, p4);
            menu.append_submenu (_("Playback"), playback);
            set_menubar (menu);
            MusicIntents.install (this);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ().copy ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.music");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var shuffle_all = new SimpleAction ("shuffle-all", null);
            shuffle_all.activate.connect (() => _shuffle_all ());
            add_action (shuffle_all);
            var open_files = new SimpleAction ("open-files", null);
            open_files.activate.connect (() => {
                show_window ();
                _window.activate_action ("open", null);
            });
            add_action (open_files);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.open", { "<Control>o" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.play-pause", { "<Control>space" });
            set_accels_for_action ("win.stop", { "<Control>period" });
            set_accels_for_action ("win.previous", { "<Control>Left" });
            set_accels_for_action ("win.next", { "<Control>Right" });
            set_accels_for_action ("win.skip-back", { "<Control><Shift>Left" });
            set_accels_for_action ("win.skip-forward", { "<Control><Shift>Right" });
            set_accels_for_action ("win.volume-up", { "<Control>Up" });
            set_accels_for_action ("win.volume-down", { "<Control>Down" });
            set_accels_for_action ("win.mute", { "<Control>m" });
            set_accels_for_action ("win.playlist", { "<Control>l" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.library", { "<Control>1" });
            set_accels_for_action ("win.now-playing", { "<Control>2" });
            set_accels_for_action ("win.lyrics", { "<Control>y" });
        }

        public Singularity.Startup.Plan build_plan (Singularity.Startup.Request request) {
            var plan = new Singularity.Startup.Plan ();
            plan.version = "music-1";
            if (request.kind == Singularity.Startup.RequestKind.SERVICE) {
                plan.main ("ready", Singularity.Startup.Category.PREPARE, (c) => {})
                    .reaches (Singularity.Startup.Milestone.SHELL_READY)
                    .reaches (Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches (Singularity.Startup.Milestone.INTERACTIVE);
                return plan;
            }
            var window = plan.main ("window", Singularity.Startup.Category.SHELL, (c) => {
                show_window ();
                c.window = _window;
            }).reaches (Singularity.Startup.Milestone.SHELL_READY);
            if (request.kind == Singularity.Startup.RequestKind.OPEN) {
                var files = request.files ();
                plan.main ("open-file", Singularity.Startup.Category.CONTENT, (c) => open_files (files))
                    .depends_on ("window")
                    .reaches (Singularity.Startup.Milestone.CONTENT_READY)
                    .reaches (Singularity.Startup.Milestone.INTERACTIVE);
            } else {
                window.reaches (Singularity.Startup.Milestone.CONTENT_READY).reaches (Singularity.Startup.Milestone.INTERACTIVE);
            }
            return plan;
        }

        public void handle_request (Singularity.Startup.Request request) {
            if (request.kind == Singularity.Startup.RequestKind.OPEN) open_files (request.files ());
            else show_window ();
        }

        private void show_window () {
            if (_window == null) _window = _new_window ();
            _window.present ();
        }

        private bool _styled = false;

        private MusicWindow _new_window () {
            string[] gst_args = {};
            unowned string[] ua = gst_args;
            Gst.init (ref ua);
            if (!_styled) {
                _setup_styles ();
                _styled = true;
            }
            return new MusicWindow (this, _search);
        }

        public void prepare_move () throws Singularity.Migration.MigrationError {
            if (_window != null && _window.remote_playback) {
                throw new Singularity.Migration.MigrationError.UNSUPPORTED (_("Music playing on a Spotify device stays on this device"));
            }
        }

        public Variant save_model () {
            return new VariantDict ().end ();
        }

        public async void restore_model (Variant model) throws Error {
        }

        public string window_kind (Gtk.Window w) {
            if (w is MusicWindow) return "music";
            if (w is MiniPlayer && _window != null) return "mini";
            return "";
        }

        public Variant save_window (Gtk.Window w) {
            return _window.save_migration ();
        }

        public string[] files () {
            return _window != null ? _window.migration_files () : new string[0];
        }

        public async Gtk.Window? rebuild_window (string kind, Variant data) throws Error {
            if (kind != "music" && kind != "mini") return null;
            if (_window != null) _window.destroy ();
            _window = _new_window ();
            _window.restore_migration (data);
            return kind == "mini" ? (_window.mini_window ?? _window) : _window;
        }

        private void _setup_styles () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_data (MUSIC_CSS.data);
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (), provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        }

        private const string MUSIC_CSS = """
/* now-playing page */
.music-now-playing.has-art * {
    color: white;
}

.music-now-cover {
    border-radius: 16px;
    box-shadow: 0 8px 40px rgba(0, 0, 0, 0.6);
    background-color: alpha(@text_color, 0.08);
}

.music-now-title {
    font-size: 22px;
    font-weight: bold;
}

.music-now-artist {
    font-size: 14px;
    opacity: 0.75;
}

.music-now-album {
    font-size: 12px;
    opacity: 0.5;
}

.music-time {
    font-size: 12px;
    opacity: 0.6;
    font-variant-numeric: tabular-nums;
}

.music-ctrl {
    min-width: 40px;
    min-height: 40px;
}

.music-play-btn {
    background-color: @accent_color;
    color: white;
    border-radius: 50%;
    min-width: 56px;
    min-height: 56px;
    padding: 0;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.4);
}

.music-play-btn:hover {
    background-color: alpha(@accent_color, 0.85);
}

.music-now-playing.has-art button.flat:hover,
.music-now-playing.has-art button.circular:hover,
.music-now-playing.has-art button.music-ctrl:hover {
    background-color: rgba(255, 255, 255, 0.15);
}

.music-now-playing scale trough {
    min-height: 4px;
}

.music-now-playing.has-art scale trough {
    background-color: rgba(255, 255, 255, 0.2);
}

.music-now-playing scale trough highlight {
    background-color: @accent_color;
}

.music-playlist-panel {
    border-right: 1px solid alpha(@border_color, 0.5);
}

.sx-control-strip {
    min-height: 36px;
}

.sx-control-strip button.flat:checked,
.sx-control-strip button.flat:checked:hover {
    background-color: alpha(@accent_color, 0.22);
    color: @accent_color;
}

.sx-control-strip .numeric {
    font-feature-settings: "tnum";
}

.music-transport-info {
    padding: 2px 8px 2px 2px;
}

.music-transport-cover,
.music-cover {
    border-radius: 6px;
    background-color: alpha(@text_color, 0.06);
}

.music-tile .music-cover {
    border-radius: 10px;
}

.music-grid > flowboxchild {
    border-radius: 12px;
    padding: 0;
}

.music-grid > flowboxchild:hover {
    background-color: alpha(@text_color, 0.06);
}

.music-lyrics {
    border-left: 1px solid alpha(@border_color, 0.5);
}

.music-lyric-line {
    font-weight: bold;
}

.music-lyric-pending {
    opacity: 0.45;
}

.music-lyric-current {
    color: @accent_color;
    opacity: 1;
}

.music-now-playing.has-art ~ revealer .music-lyrics {
    background-color: alpha(black, 0.25);
}
""";

        public void play_uris (string[] uris, bool replace) {
            show_window ();
            if (replace) _window.play_uris (uris);
            else _window.open_uris (uris);
        }

        private void open_files (GLib.File[] files) {
            show_window ();
            string[] uris = {};
            foreach (var f in files) uris += f.get_uri ();
            _window.open_uris (uris);
        }
    }

    public static int main (string[] args) {
        Intl.setlocale(GLib.LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = GLib.FileUtils.read_link("/proc/self/exe");
            locale_dir = GLib.Path.build_filename(GLib.Path.get_dirname(GLib.Path.get_dirname(exe)), "share", "locale");
        } catch (GLib.Error e) { }
        Intl.bindtextdomain("singularity-music", locale_dir);
        Intl.bind_textdomain_codeset("singularity-music", "UTF-8");
        Intl.textdomain("singularity-music");

        var app = new MusicApp ();
        return app.run (args);
    }
}
