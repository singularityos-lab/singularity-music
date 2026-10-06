using GLib;
using Gdk;

namespace Singularity.Apps.Music {

    public class TrackInfo : Object {
        public string uri { get; set; default = ""; }
        public string title { get; set; default = "Unknown Title"; }
        public string artist { get; set; default = "Unknown Artist"; }
        public string album { get; set; default = "Unknown Album"; }
        public int64 duration { get; set; default = 0; }
        public Gdk.Paintable? cover { get; set; default = null; }
        public string source_id { get; set; default = ""; }
        public string item_id { get; set; default = ""; }
        public string external_url { get; set; default = ""; }
        public string attribution { get; set; default = ""; }
        public string image_url { get; set; default = ""; }
        public Singularity.MediaSources.MediaItem? item { get; set; default = null; }
        public bool resolved { get; set; default = true; }

        public string display_duration {
            owned get {
                if (duration <= 0) return "0:00";
                int64 secs = duration / 1000000000;
                return "%d:%02d".printf ((int)(secs / 60), (int)(secs % 60));
            }
        }

        public static TrackInfo from_item (Singularity.MediaSources.MediaItem item) {
            var t = new TrackInfo ();
            t.item = item;
            t.source_id = item.source_id;
            t.item_id = item.id;
            t.title = item.title != "" ? item.title : _("Unknown Title");
            t.artist = item.artist != "" ? item.artist : (item.subtitle != "" ? item.subtitle : _("Unknown Artist"));
            t.album = item.album != "" ? item.album : _("Unknown Album");
            t.duration = item.duration_ms * 1000000;
            t.external_url = item.external_url;
            t.attribution = item.attribution;
            t.image_url = item.image_url;
            t.uri = item.stream_uri;
            t.resolved = false;
            return t;
        }

        public Singularity.MediaSources.MediaItem to_item () {
            if (item != null) return item;
            var it = new Singularity.MediaSources.MediaItem (source_id != "" ? source_id : "local", item_id != "" ? item_id : uri,
                Singularity.MediaSources.ItemKind.TRACK, title);
            it.artist = artist != _("Unknown Artist") ? artist : "";
            it.album = album != _("Unknown Album") ? album : "";
            it.duration_ms = duration / 1000000;
            it.stream_uri = uri;
            return it;
        }
    }
}
