using Gtk;

namespace Singularity.Apps.Music {

    public class TransportStrip : Box {
        private Image _cover;
        private Image _cover_icon;
        private Stack _cover_stack;
        private Label _title;
        private Label _subtitle;
        private Button _play;
        private Scale _seek;
        private Label _time;
        private bool _seeking = false;
        public ToggleButton shuffle_btn { get; private set; }
        public ToggleButton repeat_btn { get; private set; }
        public Button queue_btn { get; private set; }
        public Button prev_btn { get; private set; }
        public Button next_btn { get; private set; }

        public signal void play_pause_clicked ();
        public signal void prev_clicked ();
        public signal void next_clicked ();
        public signal void seek_requested (double fraction);
        public signal void open_player ();

        public TransportStrip () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("music-transport");
            append (new Separator (Orientation.HORIZONTAL));
            var strip = new Singularity.Widgets.ControlStrip (6, 6);
            append (strip);

            var info = new Button ();
            info.add_css_class ("flat");
            info.add_css_class ("music-transport-info");
            info.tooltip_text = _("Show Now Playing (Ctrl+2)");
            info.clicked.connect (() => open_player ());
            var info_box = new Box (Orientation.HORIZONTAL, 10);
            _cover_stack = new Stack ();
            _cover_stack.add_css_class ("music-transport-cover");
            _cover_stack.overflow = Overflow.HIDDEN;
            _cover_stack.set_size_request (36, 36);
            _cover_stack.valign = Align.CENTER;
            _cover_icon = new Image.from_icon_name ("audio-x-generic");
            _cover_icon.pixel_size = 32;
            _cover_stack.add_named (_cover_icon, "icon");
            _cover = new Image ();
            _cover.pixel_size = 36;
            _cover_stack.add_named (_cover, "art");
            info_box.append (_cover_stack);
            var labels = new Box (Orientation.VERTICAL, 0);
            labels.valign = Align.CENTER;
            _title = new Label (_("Not Playing"));
            _title.xalign = 0;
            _title.ellipsize = Pango.EllipsizeMode.END;
            _title.width_chars = 18;
            _title.max_width_chars = 28;
            _title.add_css_class ("heading");
            _subtitle = new Label ("");
            _subtitle.xalign = 0;
            _subtitle.ellipsize = Pango.EllipsizeMode.END;
            _subtitle.max_width_chars = 28;
            _subtitle.add_css_class ("dim-label");
            _subtitle.add_css_class ("caption");
            labels.append (_title);
            labels.append (_subtitle);
            info_box.append (labels);
            info.set_child (info_box);
            strip.append (info);

            prev_btn = strip.add_icon_button ("media-skip-backward-symbolic", _("Previous (Ctrl+Left)"));
            prev_btn.clicked.connect (() => prev_clicked ());
            _play = strip.add_icon_button ("media-playback-start-symbolic", _("Play or Pause (Ctrl+Space)"));
            _play.clicked.connect (() => play_pause_clicked ());
            next_btn = strip.add_icon_button ("media-skip-forward-symbolic", _("Next (Ctrl+Right)"));
            next_btn.clicked.connect (() => next_clicked ());

            _seek = new Scale.with_range (Orientation.HORIZONTAL, 0, 1, 0.001);
            _seek.draw_value = false;
            _seek.hexpand = true;
            _seek.valign = Align.CENTER;
            _seek.change_value.connect ((scroll, val) => {
                _seeking = true;
                seek_requested (val.clamp (0, 1));
                _seeking = false;
                return false;
            });
            strip.append (_seek);
            _time = strip.add_numeric_label ();
            _time.label = "0:00 / 0:00";

            shuffle_btn = strip.add_icon_toggle ("media-playlist-shuffle-symbolic", _("Shuffle"));
            repeat_btn = strip.add_icon_toggle ("media-playlist-repeat-symbolic", _("Repeat"));
            queue_btn = strip.add_icon_button ("view-list-symbolic", _("Queue (Ctrl+L)"));
            set_has_track (false);
        }

        private static string fmt (int64 ns) {
            int64 s = ns / 1000000000;
            if (s >= 3600) return "%d:%02d:%02d".printf ((int) (s / 3600), (int) (s / 60 % 60), (int) (s % 60));
            return "%d:%02d".printf ((int) (s / 60), (int) (s % 60));
        }

        public void set_has_track (bool has) {
            _play.sensitive = has;
            prev_btn.sensitive = has;
            next_btn.sensitive = has;
            _seek.sensitive = has;
        }

        public void update_track (TrackInfo? track) {
            set_has_track (track != null);
            if (track == null) {
                _title.label = _("Not Playing");
                _subtitle.label = "";
                _cover_stack.visible_child_name = "icon";
                _time.label = "0:00 / 0:00";
                _seek.set_value (0);
                return;
            }
            _title.label = track.title;
            _subtitle.label = track.artist;
            if (track.cover != null) {
                _cover.paintable = track.cover;
                _cover_stack.visible_child_name = "art";
            } else {
                _cover_stack.visible_child_name = "icon";
            }
        }

        public void set_playing (bool playing) {
            _play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
        }

        public void set_seekable (bool seekable) {
            _seek.sensitive = seekable;
        }

        public void update_position (int64 pos, int64 dur) {
            if (_seeking) return;
            _time.label = "%s / %s".printf (fmt (pos), fmt (dur));
            _seek.set_value (dur > 0 ? (double) pos / (double) dur : 0);
        }
    }
}
