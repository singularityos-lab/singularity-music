namespace Singularity.Apps.Music {

    public class PipeAudioPlayer : Object {
        private Gst.Element? _pipeline = null;
        private Gst.Element? _volume = null;
        private uint _watch = 0;
        private uint _retry = 0;
        private bool _active = false;
        private double _level = 1.0;
        private bool _muted = false;
        private int _fd = -1;

        public string path { get; construct; }
        public int sample_rate { get; construct; }
        public int channels { get; construct; }
        public int64 bytes_seen { get; private set; default = 0; }
        public int restarts { get; private set; default = 0; }

        public PipeAudioPlayer (string path, int sample_rate, int channels) {
            Object (path: path, sample_rate: sample_rate, channels: channels);
        }

        public static string sink_description () {
            string? sink = Environment.get_variable ("SINGULARITY_MUSIC_AUDIO_SINK");
            return sink != null && sink.strip () != "" ? sink : "autoaudiosink";
        }

        public string description () {
            return "fdsrc fd=%d blocksize=4096 ! rawaudioparse use-sink-caps=false format=pcm pcm-format=s16le sample-rate=%d num-channels=%d ! identity name=meter ! audioconvert ! audioresample ! volume name=vol ! %s".printf (
                _fd, sample_rate, channels, sink_description ());
        }

        public void start () {
            _active = true;
            if (_pipeline != null) return;
            if (_fd < 0) _fd = Posix.open (path, Posix.O_RDWR | Posix.O_CLOEXEC);
            if (_fd < 0) {
                warning ("music: cannot open %s", path);
                return;
            }
            try {
                _pipeline = Gst.parse_launch (description ());
            } catch (Error e) {
                warning ("music: pipe player: %s", e.message);
                return;
            }
            _volume = ((Gst.Bin) _pipeline).get_by_name ("vol");
            apply_volume ();
            var meter = ((Gst.Bin) _pipeline).get_by_name ("meter");
            if (meter != null) {
                GLib.Signal.connect (meter, "handoff", (GLib.Callback) on_handoff, this);
                meter.set_property ("signal-handoffs", true);
            }
            _watch = _pipeline.get_bus ().add_watch (Priority.DEFAULT, (bus, msg) => {
                if (msg.type == Gst.MessageType.EOS || msg.type == Gst.MessageType.ERROR) restart ();
                return true;
            });
            _pipeline.set_state (Gst.State.PLAYING);
        }

        private static void on_handoff (Gst.Element identity, Gst.Buffer buffer, PipeAudioPlayer self) {
            int64 n = (int64) buffer.get_size ();
            Idle.add (() => {
                self.bytes_seen += n;
                return Source.REMOVE;
            });
        }

        private void teardown () {
            if (_watch != 0) {
                Source.remove (_watch);
                _watch = 0;
            }
            if (_pipeline != null) {
                _pipeline.set_state (Gst.State.NULL);
                _pipeline = null;
                _volume = null;
            }
        }

        private void restart () {
            teardown ();
            if (!_active || _retry != 0) return;
            restarts++;
            _retry = Timeout.add (200, () => {
                _retry = 0;
                if (_active) start ();
                return Source.REMOVE;
            });
        }

        public void stop () {
            _active = false;
            if (_retry != 0) {
                Source.remove (_retry);
                _retry = 0;
            }
            teardown ();
            if (_fd >= 0) {
                Posix.close (_fd);
                _fd = -1;
            }
        }

        private void apply_volume () {
            if (_volume == null) return;
            _volume.set_property ("volume", _level);
            _volume.set_property ("mute", _muted);
        }

        public void set_volume (double v) {
            _level = v.clamp (0, 1);
            apply_volume ();
        }

        public void set_muted (bool m) {
            _muted = m;
            apply_volume ();
        }
    }
}
