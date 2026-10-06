using Gst;
using Gdk;
using GLib;

namespace Singularity.Apps.Music {

    public class GstAudioPlayer : GLib.Object, PlayerBackend {
        private Gst.Element? _playbin;
        private uint _bus_watch_id = 0;
        private uint _pos_timer_id = 0;
        private bool _is_playing = false;

        private HashTable<string, string>? _headers = null;

        public bool is_playing { get { return _is_playing; } }
        public bool can_seek { get { return true; } }

        public GstAudioPlayer () {
            _playbin = Gst.ElementFactory.make ("playbin", "playbin");
            if (_playbin == null) {
                warning ("GstAudioPlayer: could not create playbin");
                return;
            }

            GLib.Signal.connect (_playbin, "source-setup", (GLib.Callback) _on_source_setup, this);
            string? sink = Environment.get_variable ("SINGULARITY_MUSIC_AUDIO_SINK");
            if (sink != null && sink.strip () != "") {
                try {
                    _playbin.set_property ("audio-sink", Gst.parse_bin_from_description (sink, true));
                } catch (Error e) {
                    warning ("GstAudioPlayer: %s", e.message);
                }
            }
            var bus = _playbin.get_bus ();
            _bus_watch_id = bus.add_watch (GLib.Priority.DEFAULT, _on_bus_message);

            _pos_timer_id = GLib.Timeout.add (250, () => {
                if (!_is_playing) return GLib.Source.CONTINUE;
                int64 pos = 0, dur = 0;
                _playbin.query_position (Gst.Format.TIME, out pos);
                _playbin.query_duration (Gst.Format.TIME, out dur);
                position_updated (pos, dur);
                return GLib.Source.CONTINUE;
            });
        }

        ~GstAudioPlayer () {
            if (_pos_timer_id != 0) GLib.Source.remove (_pos_timer_id);
            if (_bus_watch_id != 0) GLib.Source.remove (_bus_watch_id);
            _playbin?.set_state (Gst.State.NULL);
        }

        private bool _on_bus_message (Gst.Bus bus, Gst.Message msg) {
            switch (msg.type) {
            case Gst.MessageType.EOS:
                _set_playing (false);
                track_ended ();
                break;
            case Gst.MessageType.ERROR:
                GLib.Error err;
                string dbg;
                msg.parse_error (out err, out dbg);
                error_occurred (err.message);
                break;
            case Gst.MessageType.TAG:
                Gst.TagList tags;
                msg.parse_tag (out tags);
                _parse_tags (tags);
                break;
            }
            return true;
        }

        private void _parse_tags (Gst.TagList tags) {
            string? title = null, artist = null, album = null;
            int64 dur = 0;
            Gdk.Paintable? cover = null;

            tags.get_string (Gst.Tags.TITLE, out title);
            tags.get_string (Gst.Tags.ARTIST, out artist);
            tags.get_string (Gst.Tags.ALBUM, out album);

            // Try to extract embedded album art
            Gst.Sample? sample = null;
            if (tags.get_sample (Gst.Tags.IMAGE, out sample) && sample != null) {
                var buf = sample.get_buffer ();
                if (buf != null) {
                    Gst.MapInfo minfo;
                    if (buf.map (out minfo, Gst.MapFlags.READ)) {
                        try {
                            var loader = new Gdk.PixbufLoader ();
                            loader.write (minfo.data);
                            loader.close ();
                            var pixbuf = loader.get_pixbuf ();
                            if (pixbuf != null) cover = Gdk.Texture.for_pixbuf (pixbuf);
                        } catch {}
                        buf.unmap (minfo);
                    }
                }
            }

            _playbin.query_duration (Gst.Format.TIME, out dur);
            metadata_ready (title, artist, album, dur, cover);
        }

        private static void _on_source_setup (Gst.Element playbin, Gst.Element source, GstAudioPlayer self) {
            if (self._headers == null || source.get_class ().find_property ("extra-headers") == null) return;
            var s = new Gst.Structure.empty ("extra-headers");
            self._headers.foreach ((k, v) => {
                if (k.down () == "user-agent" && source.get_class ().find_property ("user-agent") != null) source.set_property ("user-agent", v);
                else s.set_value (k, v);
            });
            source.set_property ("extra-headers", s);
        }

        public void set_headers (HashTable<string, string>? headers) {
            _headers = headers;
        }

        public void load_uri (string uri) {
            _playbin.set_state (Gst.State.NULL);
            _playbin.set_property ("uri", uri);
            _set_playing (false);
        }

        private void _set_playing (bool playing) {
            if (_is_playing == playing) return;
            _is_playing = playing;
            playing_changed (playing);
        }

        public void play () {
            if (_playbin == null) return;
            _playbin.set_state (Gst.State.PLAYING);
            _set_playing (true);
        }

        public void pause () {
            _playbin?.set_state (Gst.State.PAUSED);
            _set_playing (false);
        }

        public void stop () {
            _playbin?.set_state (Gst.State.NULL);
            _set_playing (false);
        }

        public void seek (int64 pos_ns) {
            _playbin?.seek_simple (Gst.Format.TIME,
                Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, pos_ns);
        }

        public void set_volume (double vol) {
            _playbin?.set_property ("volume", vol);
        }

        public void set_muted (bool muted) {
            _playbin?.set_property ("mute", muted);
        }

        public int64 get_position () {
            int64 pos = 0;
            _playbin?.query_position (Gst.Format.TIME, out pos);
            return pos;
        }

        public int64 get_duration () {
            int64 dur = 0;
            _playbin?.query_duration (Gst.Format.TIME, out dur);
            return dur;
        }
    }
}
