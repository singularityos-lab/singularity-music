using Gtk;
using GLib;

namespace Singularity.Apps.Music {

    public class MusicApp : Singularity.Application {

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
                else activate ();
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
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
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
                activate ();
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

        protected override void activate () {
            string[] gst_args = {};
            unowned string[] ua = gst_args;
            Gst.init (ref ua);

            if (_window == null) {
                _setup_styles ();
                _window = new MusicWindow (this, _search);
            }
            _window.present ();
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
            activate ();
            if (replace) _window.play_uris (uris);
            else _window.open_uris (uris);
        }

        protected override void open (GLib.File[] files, string hint) {
            activate ();
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
