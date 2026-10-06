using Gtk;
using GLib;

namespace Singularity.Apps.Music {

    public class MiniPlayer : Gtk.Window {
        private Gtk.Image _cover_img;
        private Gtk.Label _title_lbl;
        private Gtk.Label _artist_lbl;
        private Gtk.Button _play_btn;
        private Gtk.Scale _seek_bar;
        private bool _seeking = false;

        public signal void play_pause_clicked ();
        public signal void prev_clicked ();
        public signal void next_clicked ();
        public signal void seek_requested (double fraction);
        public signal void expand_clicked ();

        public MiniPlayer (Gtk.Application app) {
            Object (application: app);
            resizable = false;
            decorated = false;
            default_width = 340;
            default_height = 90;
            add_css_class ("mini-player");
            _build_ui ();
        }

        private void _build_ui () {
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.add_css_class ("mini-player-box");

            // Album art
            _cover_img = new Image.from_icon_name ("audio-x-generic");
            _cover_img.pixel_size = 64;
            _cover_img.add_css_class ("mini-player-cover");
            _cover_img.margin_start = 12;
            _cover_img.margin_end = 12;
            _cover_img.valign = Align.CENTER;
            box.append (_cover_img);

            // Title + artist + seek bar
            var info_box = new Box (Orientation.VERTICAL, 2);
            info_box.valign = Align.CENTER;
            info_box.hexpand = true;
            info_box.margin_end = 8;

            _title_lbl = new Label (_("No track playing"));
            _title_lbl.add_css_class ("mini-player-title");
            _title_lbl.halign = Align.START;
            _title_lbl.ellipsize = Pango.EllipsizeMode.END;
            _title_lbl.max_width_chars = 22;
            info_box.append (_title_lbl);

            _artist_lbl = new Label ("");
            _artist_lbl.add_css_class ("mini-player-artist");
            _artist_lbl.halign = Align.START;
            _artist_lbl.ellipsize = Pango.EllipsizeMode.END;
            _artist_lbl.max_width_chars = 22;
            info_box.append (_artist_lbl);

            _seek_bar = new Scale.with_range (Orientation.HORIZONTAL, 0, 1, 0.001);
            _seek_bar.draw_value = false;
            _seek_bar.hexpand = true;
            _seek_bar.add_css_class ("mini-seek");
            _seek_bar.margin_top = 4;
            _seek_bar.change_value.connect ((scroll, val) => {
                _seeking = true;
                seek_requested (val);
                _seeking = false;
                return false;
            });
            info_box.append (_seek_bar);

            box.append (info_box);

            // Playback controls
            var ctrl_box = new Box (Orientation.HORIZONTAL, 4);
            ctrl_box.valign = Align.CENTER;
            ctrl_box.margin_end = 8;

            var prev_btn = new Button.from_icon_name ("media-skip-backward-symbolic");
            prev_btn.add_css_class ("flat");
            prev_btn.add_css_class ("circular");
            prev_btn.tooltip_text = _("Previous");
            prev_btn.clicked.connect (() => prev_clicked ());

            _play_btn = new Button.from_icon_name ("media-playback-start-symbolic");
            _play_btn.add_css_class ("flat");
            _play_btn.add_css_class ("circular");
            _play_btn.tooltip_text = _("Play / Pause");
            _play_btn.clicked.connect (() => play_pause_clicked ());

            var next_btn = new Button.from_icon_name ("media-skip-forward-symbolic");
            next_btn.add_css_class ("flat");
            next_btn.add_css_class ("circular");
            next_btn.tooltip_text = _("Next");
            next_btn.clicked.connect (() => next_clicked ());

            var expand_btn = new Button.from_icon_name ("view-restore-symbolic");
            expand_btn.add_css_class ("flat");
            expand_btn.add_css_class ("circular");
            expand_btn.tooltip_text = _("Open full player");
            expand_btn.clicked.connect (() => expand_clicked ());

            ctrl_box.append (prev_btn);
            ctrl_box.append (_play_btn);
            ctrl_box.append (next_btn);
            ctrl_box.append (expand_btn);

            box.append (ctrl_box);
            set_child (box);
        }

        public void update_track (TrackInfo? track) {
            if (track == null) {
                _title_lbl.label = _("No track playing");
                _artist_lbl.label = "";
                _cover_img.paintable = null;
                _cover_img.icon_name = "audio-x-generic";
                return;
            }
            _title_lbl.label = track.title;
            _artist_lbl.label = track.artist;
            if (track.cover != null) {
                _cover_img.paintable = track.cover;
            } else {
                _cover_img.paintable = null;
                _cover_img.icon_name = "audio-x-generic";
            }
        }

        public void update_playback (bool playing) {
            _play_btn.icon_name = playing
                ? "media-playback-pause-symbolic"
                : "media-playback-start-symbolic";
        }

        public void reset_position () {
            _seek_bar.set_value (0);
        }

        public void update_position (int64 pos, int64 dur) {
            if (_seeking || dur <= 0) return;
            _seek_bar.set_value ((double) pos / (double) dur);
        }
    }
}
