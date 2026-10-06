using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class RemoteBackend : Object, PlayerBackend {
        private RemotePlayer _remote;
        private MediaItem? _item = null;
        private MediaItem? _context = null;
        private bool _playing = false;
        private string _last_key = "";
        private bool _active = false;
        private uint _tick = 0;
        private int64 _base_pos = 0;
        private int64 _base_time = 0;

        public bool is_playing { get { return _playing; } }
        public bool can_seek { get { return true; } }
        public RemotePlayer remote { get { return _remote; } }

        public RemoteBackend (RemotePlayer remote) {
            _remote = remote;
            _remote.state_changed.connect (_sync);
        }

        public void start (MediaItem item, MediaItem? context) {
            _item = item;
            _context = context;
            _last_key = item.key;
            _active = true;
            _remote.set_active (true);
            _remote.play_item.begin (item, context, (o, r) => {
                try {
                    _remote.play_item.end (r);
                } catch (Error e) {
                    error_occurred (e.message);
                }
            });
            if (_tick == 0) _tick = Timeout.add (500, () => {
                if (!_active) {
                    _tick = 0;
                    return Source.REMOVE;
                }
                int64 dur = _remote.duration_ms * 1000000;
                position_updated (get_position (), dur);
                return Source.CONTINUE;
            });
        }

        public void detach () {
            _active = false;
            _remote.set_active (false);
        }

        private void _sync () {
            if (!_active) return;
            bool playing = _remote.state == PlaybackState.PLAYING;
            _base_pos = _remote.position_ms * 1000000;
            _base_time = get_monotonic_time ();
            if (playing != _playing) {
                _playing = playing;
                playing_changed (playing);
            }
            var cur = _remote.current;
            if (cur != null && cur.key != _last_key) {
                _last_key = cur.key;
                metadata_ready (cur.title, cur.artist, cur.album, cur.duration_ms * 1000000, null);
            }
        }

        private void run (int kind, int64 arg = 0) {
            run_async.begin (kind, arg);
        }

        private async void run_async (int kind, int64 arg) {
            try {
                switch (kind) {
                    case 0: yield _remote.resume (); break;
                    case 1: yield _remote.pause (); break;
                    case 2: yield _remote.seek (arg); break;
                    default: yield _remote.set_volume ((double) arg / 1000.0); break;
                }
            } catch (Error e) {
                error_occurred (e.message);
            }
        }

        public void load_uri (string uri) {
        }

        public void play () {
            run (0);
        }

        public void pause () {
            run (1);
        }

        public void stop () {
            if (_playing) run (1);
            detach ();
        }

        public void seek (int64 pos_ns) {
            run (2, pos_ns / 1000000);
        }

        public void set_volume (double vol) {
            run (3, (int64) (vol * 1000));
        }

        public void set_muted (bool muted) {
            if (muted) run (3, 0);
        }

        public int64 get_position () {
            int64 pos = _base_pos;
            if (_playing && _base_time > 0) pos += (get_monotonic_time () - _base_time) * 1000;
            int64 dur = get_duration ();
            if (dur > 0 && pos > dur) pos = dur;
            return pos;
        }

        public int64 get_duration () {
            return _remote.duration_ms * 1000000;
        }
    }
}
