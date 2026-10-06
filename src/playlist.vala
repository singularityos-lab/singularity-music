using GLib;
using Gee;

namespace Singularity.Apps.Music {

    public class Playlist : Object {
        private ArrayList<TrackInfo> _tracks = new ArrayList<TrackInfo> ();
        private int _current = -1;
        private bool _shuffle = false;
        private bool _repeat_one = false;
        private bool _repeat_all = false;

        public signal void track_added (TrackInfo track);
        public signal void track_inserted (int index, TrackInfo track);
        public signal void track_removed (int index);
        public signal void current_changed (TrackInfo? track);
        public signal void cleared ();

        public int count { get { return _tracks.size; } }
        public int current_index { get { return _current; } }
        public bool shuffle { get { return _shuffle; } set { _shuffle = value; } }
        public bool repeat_one { get { return _repeat_one; } set { _repeat_one = value; } }
        public bool repeat_all { get { return _repeat_all; } set { _repeat_all = value; } }

        public TrackInfo? current_track {
            owned get {
                if (_current < 0 || _current >= _tracks.size) return null;
                return _tracks[_current];
            }
        }

        public void add_uri (string uri) {
            var t = new TrackInfo ();
            t.uri = uri;
            var f = File.new_for_uri (uri);
            string name = f.get_basename () ?? uri;
            if (name.contains (".")) name = name.substring (0, name.last_index_of ("."));
            t.title = name;
            _tracks.add (t);
            track_added (t);
        }

        public void add_uris (string[] uris) {
            foreach (var u in uris) add_uri (u);
        }

        public void add_track (TrackInfo track) {
            _tracks.add (track);
            track_added (track);
        }

        public void insert_next (TrackInfo track) {
            int at = _current + 1;
            if (at < 0 || at > _tracks.size) at = _tracks.size;
            _tracks.insert (at, track);
            track_inserted (at, track);
        }

        public TrackInfo? get_track (int i) {
            return (i >= 0 && i < _tracks.size) ? _tracks[i] : null;
        }

        public ArrayList<TrackInfo> get_all () { return _tracks; }

        public TrackInfo? play_index (int i) {
            if (i < 0 || i >= _tracks.size) return null;
            _current = i;
            current_changed (_tracks[_current]);
            return _tracks[_current];
        }

        public TrackInfo? next () {
            if (_tracks.size == 0) return null;
            if (_repeat_one && _current >= 0) return play_index (_current);
            if (_shuffle) return play_index (GLib.Random.int_range (0, _tracks.size));
            int n = _current + 1;
            if (n >= _tracks.size) {
                if (_repeat_all) n = 0;
                else return null;
            }
            return play_index (n);
        }

        public TrackInfo? prev () {
            if (_tracks.size == 0) return null;
            int n = _current - 1;
            if (n < 0) n = _repeat_all ? _tracks.size - 1 : 0;
            return play_index (n);
        }

        public void clear () {
            _tracks.clear ();
            _current = -1;
            cleared ();
        }

        public void remove_at (int i) {
            if (i < 0 || i >= _tracks.size) return;
            _tracks.remove_at (i);
            if (_current >= _tracks.size) _current = _tracks.size - 1;
            track_removed (i);
        }
    }
}
