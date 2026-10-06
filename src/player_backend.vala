namespace Singularity.Apps.Music {

    public interface PlayerBackend : Object {
        public signal void position_updated (int64 pos, int64 dur);
        public signal void track_ended ();
        public signal void error_occurred (string msg);
        public signal void metadata_ready (string? title, string? artist, string? album, int64 duration, Gdk.Paintable? cover);
        public signal void playing_changed (bool playing);

        public abstract bool is_playing { get; }
        public abstract bool can_seek { get; }

        public abstract void load_uri (string uri);
        public abstract void play ();
        public abstract void pause ();
        public abstract void stop ();
        public abstract void seek (int64 pos_ns);
        public abstract void set_volume (double vol);
        public abstract void set_muted (bool muted);
        public abstract int64 get_position ();
        public abstract int64 get_duration ();

        public void toggle_play_pause () {
            if (is_playing) pause (); else play ();
        }
    }
}
