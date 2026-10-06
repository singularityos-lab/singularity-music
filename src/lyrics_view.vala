using Gtk;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class LyricsView : Box {
        private Stack _stack;
        private ScrolledWindow _scroll;
        private Box _lines;
        private Label _status;
        private Label _credit;
        private Lyrics? _lyrics = null;
        private Gee.ArrayList<Label> _labels = new Gee.ArrayList<Label> ();
        private int _current = -1;

        public LyricsView () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("music-lyrics");
            set_size_request (280, -1);
            _stack = new Stack ();
            _stack.vexpand = true;
            _scroll = new ScrolledWindow ();
            _scroll.hscrollbar_policy = PolicyType.NEVER;
            _lines = new Box (Orientation.VERTICAL, 10);
            _lines.margin_start = 24;
            _lines.margin_end = 24;
            _lines.margin_top = 48;
            _lines.margin_bottom = 120;
            _scroll.set_child (_lines);
            _stack.add_named (_scroll, "lines");
            _status = new Label ("");
            _status.wrap = true;
            _status.justify = Justification.CENTER;
            _status.add_css_class ("dim-label");
            _status.margin_start = 24;
            _status.margin_end = 24;
            _stack.add_named (_status, "status");
            append (_stack);
            _credit = new Label ("");
            _credit.add_css_class ("caption");
            _credit.add_css_class ("dim-label");
            _credit.margin_bottom = 12;
            _credit.margin_top = 6;
            _credit.ellipsize = Pango.EllipsizeMode.END;
            append (_credit);
            show_message (_("No lyrics"));
        }

        public void show_message (string text) {
            _lyrics = null;
            _status.label = text;
            _stack.visible_child_name = "status";
            _credit.label = "";
        }

        public void set_lyrics (Lyrics lyrics) {
            _lyrics = lyrics;
            _labels.clear ();
            _current = -1;
            Widget? c;
            while ((c = _lines.get_first_child ()) != null) _lines.remove (c);
            if (lyrics.instrumental) {
                show_message (_("Instrumental"));
                return;
            }
            foreach (var line in lyrics.lines) {
                var l = new Label (line.text);
                l.wrap = true;
                l.xalign = 0;
                l.add_css_class ("music-lyric-line");
                l.add_css_class ("title-3");
                if (lyrics.synced) l.add_css_class ("music-lyric-pending");
                _lines.append (l);
                _labels.add (l);
            }
            _credit.label = lyrics.attribution != "" ? _("Lyrics from %s").printf (lyrics.attribution) : "";
            _stack.visible_child_name = "lines";
            _scroll.vadjustment.value = 0;
        }

        public void update_position (int64 pos_ns) {
            if (_lyrics == null || !_lyrics.synced) return;
            int idx = _lyrics.index_at (pos_ns / 1000000);
            if (idx == _current) return;
            if (_current >= 0 && _current < _labels.size) _labels[_current].remove_css_class ("music-lyric-current");
            _current = idx;
            for (int i = 0; i < _labels.size; i++) {
                if (i <= idx) _labels[i].remove_css_class ("music-lyric-pending");
                else _labels[i].add_css_class ("music-lyric-pending");
            }
            if (idx < 0 || idx >= _labels.size) return;
            var l = _labels[idx];
            l.add_css_class ("music-lyric-current");
            Graphene.Point p = {};
            Graphene.Point src = { 0, 0 };
            if (l.compute_point (_lines, src, out p)) {
                double target = p.y - _scroll.get_height () / 3.0;
                _scroll.vadjustment.value = double.max (0, target);
            }
        }
    }
}
