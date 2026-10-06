using Gtk;
using Gdk;

namespace Singularity.Apps.Music {

    /**
     * Full-screen now-playing widget.
     *
     * The static layout lives in ui/now_playing.vetro; this class draws the
     * album-art background via snapshot(), extracts the dominant cover colour
     * as an accent, and wires the transport signals.
     */
    [GtkTemplate(ui = "/dev/sinty/music/ui/now_playing.ui")]
    public class NowPlayingPage : Gtk.Box {

        // ── Background / accent ───────────────────────────────────────────
        private Gdk.Texture?        _bg_texture   = null;
        private Gtk.CssProvider?    _css_provider = null;

        [GtkChild (name = "content_box")] unowned Box _content_box;

        // ── Cover art ────────────────────────────────────────────────────
        [GtkChild (name = "cover_stack")] unowned Stack _cover_stack;
        private Picture          _cover_pic;

        // ── Labels ───────────────────────────────────────────────────────
        [GtkChild (name = "title_lbl")]  unowned Label _title_lbl;
        [GtkChild (name = "artist_lbl")] unowned Label _artist_lbl;
        [GtkChild (name = "album_lbl")]  unowned Label _album_lbl;

        // ── Transport ────────────────────────────────────────────────────
        [GtkChild (name = "seek_bar")]    unowned Scale  _seek_bar;
        [GtkChild (name = "pos_lbl")]     unowned Label  _pos_lbl;
        [GtkChild (name = "dur_lbl")]     unowned Label  _dur_lbl;
        [GtkChild (name = "play_btn")]    unowned Button _play_btn;
        [GtkChild (name = "shuffle_btn")] unowned Button _shuffle_btn;
        [GtkChild (name = "prev_btn")]    unowned Button _prev_btn;
        [GtkChild (name = "next_btn")]    unowned Button _next_btn;
        [GtkChild (name = "repeat_btn")]  unowned Button _repeat_btn;
        [GtkChild (name = "vol_lo")]      unowned Image  _vol_lo;
        [GtkChild (name = "vol_hi")]      unowned Image  _vol_hi;
        [GtkChild (name = "vol_slider")]  unowned Scale  _vol_slider;
        private bool _seeking = false;

        /** Button to anchor the playlist popover. */
        [GtkChild] public unowned Button playlist_btn;

        // ── Signals ──────────────────────────────────────────────────────
        public signal void play_pause_clicked ();
        public signal void prev_clicked ();
        public signal void next_clicked ();
        public signal void shuffle_clicked ();
        public signal void repeat_clicked ();
        public signal void seek_requested (double fraction);
        public signal void volume_changed (double vol);

        // ── Constructor ──────────────────────────────────────────────────

        public NowPlayingPage () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            overflow  = Gtk.Overflow.HIDDEN;
            hexpand   = true;
            vexpand   = true;
            add_css_class ("music-now-playing");
            append (_content_box);

            // Cover-art stack pages (Gtk.Stack named children built here).
            var fallback = new Image.from_icon_name ("audio-x-generic");
            fallback.pixel_size = 96;
            fallback.valign     = Align.CENTER;
            fallback.halign     = Align.CENTER;
            _cover_stack.add_named (fallback, "icon");

            _cover_pic = new Picture ();
            _cover_pic.content_fit = ContentFit.COVER;
            _cover_pic.can_shrink  = true;
            _cover_stack.add_named (_cover_pic, "art");
            _cover_stack.visible_child_name = "icon";
            _cover_stack.overflow = Overflow.HIDDEN;

            _vol_lo.opacity = 0.7;
            _vol_hi.opacity = 0.7;

            // Transport wiring.
            _seek_bar.set_range (0, 1);
            _seek_bar.change_value.connect ((scroll, val) => {
                _seeking = true;
                seek_requested (val.clamp (0, 1));
                _seeking = false;
                return false;
            });
            _shuffle_btn.clicked.connect (() => shuffle_clicked ());
            _prev_btn.clicked.connect (() => prev_clicked ());
            _play_btn.clicked.connect (() => play_pause_clicked ());
            _next_btn.clicked.connect (() => next_clicked ());
            _repeat_btn.clicked.connect (() => repeat_clicked ());

            _vol_slider.set_range (0, 1);
            _vol_slider.set_value (1.0);
            _vol_slider.value_changed.connect (() => volume_changed (_vol_slider.get_value ()));
        }

        public double volume {
            get { return _vol_slider.get_value (); }
            set { _vol_slider.set_value (value.clamp (0, 1)); }
        }

        // ── Public update API ─────────────────────────────────────────────

        public void update_track (TrackInfo? track) {
            if (track == null) {
                _title_lbl.label  = _("No track playing");
                _artist_lbl.label = "";
                _album_lbl.label  = "";
                _cover_stack.visible_child_name = "icon";
                _set_bg (null);
                _reset_accent ();
                return;
            }
            _title_lbl.label  = track.title;
            _artist_lbl.label = track.artist;
            _album_lbl.label  = (track.album != _("Unknown Album")) ? track.album : "";
            if (track.cover != null) {
                _cover_pic.paintable = track.cover;
                _cover_stack.visible_child_name = "art";
                if (track.cover is Gdk.Texture) {
                    var tex = (Gdk.Texture) track.cover;
                    _set_bg (tex);
                    _apply_accent_from_texture (tex);
                }
            } else {
                _cover_stack.visible_child_name = "icon";
                _set_bg (null);
                _reset_accent ();
            }
        }

        public void update_position (int64 pos, int64 dur) {
            if (_seeking || dur <= 0) return;
            _pos_lbl.label = _fmt (pos);
            _dur_lbl.label = _fmt (dur);
            _seek_bar.set_value ((double) pos / (double) dur);
        }

        public void reset_position () {
            _pos_lbl.label = _fmt (0);
            _dur_lbl.label = _fmt (0);
            _seek_bar.set_value (0);
        }

        public void set_playing (bool playing) {
            _play_btn.icon_name = playing
                ? "media-playback-pause-symbolic"
                : "media-playback-start-symbolic";
        }

        public void set_shuffle_active (bool active) {
            if (active) _shuffle_btn.add_css_class ("accent");
            else        _shuffle_btn.remove_css_class ("accent");
        }

        public void set_repeat_state (int mode) {
            switch (mode) {
            case 0:
                _repeat_btn.icon_name = "media-playlist-repeat-symbolic";
                _repeat_btn.remove_css_class ("accent");
                break;
            case 1:
                _repeat_btn.icon_name = "media-playlist-repeat-symbolic";
                _repeat_btn.add_css_class ("accent");
                break;
            case 2:
                _repeat_btn.icon_name = "media-playlist-repeat-song-symbolic";
                _repeat_btn.add_css_class ("accent");
                break;
            }
        }

        // ── Background (snapshot override) ───────────────────────────────

        private void _set_bg (Gdk.Texture? tex) {
            _bg_texture = tex;
            if (tex != null) add_css_class ("has-art");
            else             remove_css_class ("has-art");
            queue_draw ();
        }

        protected override void snapshot (Gtk.Snapshot snap) {
            if (_bg_texture != null) {
                float w = (float) get_width ();
                float h = (float) get_height ();

                float tw    = (float) _bg_texture.width;
                float th    = (float) _bg_texture.height;
                float scale = float.max (w / tw, h / th);
                float dw    = tw * scale;
                float dh    = th * scale;

                var draw_rect = Graphene.Rect ();
                draw_rect.init ((w - dw) / 2.0f, (h - dh) / 2.0f, dw, dh);

                snap.push_opacity (0.25);
                snap.append_texture (_bg_texture, draw_rect);
                snap.pop ();

                var dark = Gdk.RGBA ();
                dark.red = 0.04f; dark.green = 0.02f; dark.blue = 0.07f;
                dark.alpha = 0.62f;
                var full = Graphene.Rect ();
                full.init (0, 0, w, h);
                snap.append_color (dark, full);
            }
            base.snapshot (snap);
        }

        // ── Dominant colour extraction ────────────────────────────────────

        /**
         * Samples the texture pixels, finds the dominant vibrant hue via
         * circular averaging (weighted by saturation × value), then maps it
         * to a vivid colour (S≈0.72, L≈0.62) suitable for use as an accent
         * on a dark background.
         */
        private void _apply_accent_from_texture (Gdk.Texture tex) {
            int w = tex.width;
            int h = tex.height;
            if (w <= 0 || h <= 0) { _reset_accent (); return; }

            int stride = w * 4;
            uint8[] data = new uint8[stride * h];
            tex.download (data, stride);

            // Circular hue averaging: accumulate unit vectors on the hue circle,
            // weighted by saturation × value so grey/dark pixels are ignored.
            double sin_sum = 0, cos_sum = 0, weight_total = 0;
            int step_x = int.max (1, w / 32);
            int step_y = int.max (1, h / 32);

            for (int y = 0; y < h; y += step_y) {
                for (int x = 0; x < w; x += step_x) {
                    int idx = y * stride + x * 4;
                    double a = data[idx + 3] / 255.0;
                    if (a < 0.5) continue;

                    // ARGB32 (native little-endian): B G R A
                    double b_px = data[idx + 0] / 255.0;
                    double g_px = data[idx + 1] / 255.0;
                    double r_px = data[idx + 2] / 255.0;

                    double max_c = double.max (r_px, double.max (g_px, b_px));
                    double min_c = double.min (r_px, double.min (g_px, b_px));
                    double v = max_c;
                    double s = (max_c > 0) ? (max_c - min_c) / max_c : 0;

                    if (s < 0.15) continue; // skip greys

                    double hue = 0;
                    double d = max_c - min_c;
                    if (max_c == r_px)      hue = (g_px - b_px) / d + (g_px < b_px ? 6 : 0);
                    else if (max_c == g_px) hue = (b_px - r_px) / d + 2;
                    else                    hue = (r_px - g_px) / d + 4;
                    hue /= 6.0;

                    double w_pixel = s * v;
                    sin_sum      += Math.sin (2 * Math.PI * hue) * w_pixel;
                    cos_sum      += Math.cos (2 * Math.PI * hue) * w_pixel;
                    weight_total += w_pixel;
                }
            }

            if (weight_total < 0.01) { _reset_accent (); return; }

            double avg_hue = Math.atan2 (sin_sum / weight_total,
                                         cos_sum / weight_total) / (2 * Math.PI);
            if (avg_hue < 0) avg_hue += 1.0;

            // Build a vibrant colour: dominant hue, high S, mid-high L
            Gdk.RGBA accent = _hsl_to_rgba (avg_hue, 0.72, 0.62);
            _apply_accent (accent);
        }

        private void _reset_accent () {
            // Remove custom provider -> falls back to @accent_color in CSS
            if (_css_provider != null) {
                get_style_context ().remove_provider (_css_provider);
                _css_provider = null;
            }
        }

        private void _apply_accent (Gdk.RGBA color) {
            string hex = _rgba_to_hex (color);
            string css = """
                .music-play-btn {
                    background-color: %s;
                }
                .music-play-btn:hover {
                    background-color: alpha(%s, 0.82);
                }
                .music-now-playing scale trough highlight {
                    background-color: %s;
                }
                .music-ctrl.accent {
                    color: %s;
                }
            """.printf (hex, hex, hex, hex);

            var prov = new Gtk.CssProvider ();
            prov.load_from_string (css);

            if (_css_provider != null)
                get_style_context ().remove_provider (_css_provider);

            _css_provider = prov;
            get_style_context ().add_provider (_css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_USER + 10);
        }

        // ── Colour math helpers ───────────────────────────────────────────

        private Gdk.RGBA _hsl_to_rgba (double h, double s, double l) {
            double r, g, b;
            if (s == 0) {
                r = g = b = l;
            } else {
                double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
                double p = 2 * l - q;
                r = _hue_to_rgb (p, q, h + 1.0 / 3.0);
                g = _hue_to_rgb (p, q, h);
                b = _hue_to_rgb (p, q, h - 1.0 / 3.0);
            }
            var rgba = Gdk.RGBA ();
            rgba.red   = (float) r;
            rgba.green = (float) g;
            rgba.blue  = (float) b;
            rgba.alpha = 1.0f;
            return rgba;
        }

        private double _hue_to_rgb (double p, double q, double t) {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6.0) return p + (q - p) * 6 * t;
            if (t < 0.5)        return q;
            if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6;
            return p;
        }

        private string _rgba_to_hex (Gdk.RGBA c) {
            int r = (int)(c.red   * 255).clamp (0, 255);
            int g = (int)(c.green * 255).clamp (0, 255);
            int b = (int)(c.blue  * 255).clamp (0, 255);
            return "#%02X%02X%02X".printf (r, g, b);
        }

        // ── Helpers ───────────────────────────────────────────────────────

        private string _fmt (int64 ns) {
            int64 s = ns / 1000000000;
            return "%d:%02d".printf ((int)(s / 60), (int)(s % 60));
        }
    }
}
