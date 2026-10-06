using Gtk;
using Singularity.Widgets;
using Singularity.MediaSources;

namespace Singularity.Apps.Music {

    public class MediaBin : AppSidebar {
        private Box _listen = new Box (Orientation.VERTICAL, 0);
        private Box _library = new Box (Orientation.VERTICAL, 0);
        private Box _sources = new Box (Orientation.VERTICAL, 0);
        private Box _services = new Box (Orientation.VERTICAL, 0);
        private SidebarSectionLabel _sources_label;
        private SidebarSectionLabel _services_label;
        private Gee.HashMap<string, SidebarRow> _rows = new Gee.HashMap<string, SidebarRow> ();
        private SidebarRow _now_row;
        private string _active = "";
        private SearchBubble _search;

        public signal void navigate (string source_id, string? node, string title);
        public signal void now_playing_selected ();
        public signal void search_changed (string text);
        public signal void open_files ();

        public MediaBin () {
            base (240);
            add_css_class ("sx-media-bin");
            add_bubble_icon ("list-add-symbolic", _("Open Files"), () => open_files ());
            _search = add_bubble_search (_("Search"), (t) => search_changed (t));

            box.append (_listen);
            _now_row = new SidebarRow ("media-playback-start-symbolic", _("Now Playing"));
            _now_row.clicked.connect (() => {
                set_active ("now");
                now_playing_selected ();
            });
            _now_row.visible = false;
            _listen.append (_now_row);

            box.append (new SidebarSectionLabel (_("Library")));
            box.append (_library);
            add_row (_library, LocalSource.ID, "songs", "audio-x-generic-symbolic", _("Songs"));
            add_row (_library, LocalSource.ID, "albums", "media-optical-symbolic", _("Albums"));
            add_row (_library, LocalSource.ID, "artists", "avatar-default-symbolic", _("Artists"));

            _sources_label = new SidebarSectionLabel (_("Sources"));
            box.append (_sources_label);
            box.append (_sources);
            _services_label = new SidebarSectionLabel (_("Services"));
            box.append (_services_label);
            box.append (_services);
            update_sections ();
        }

        private static string key (string source_id, string? node) {
            return source_id + "|" + (node ?? "");
        }

        private SidebarRow add_row (Box parent, string source_id, string? node, string icon, string title) {
            var row = new SidebarRow (icon, title);
            string k = key (source_id, node);
            row.clicked.connect (() => {
                set_active (k);
                navigate (source_id, node, title);
            });
            _rows[k] = row;
            parent.append (row);
            return row;
        }

        public void set_active (string k) {
            _active = k;
            _now_row.set_active (k == "now");
            foreach (var e in _rows.entries) e.value.set_active (e.key == k);
        }

        public void select (string source_id, string? node) {
            set_active (key (source_id, node));
        }

        public void focus_search () {
            _search.grab_focus_entry ();
        }

        public void show_now_playing (bool visible) {
            _now_row.visible = visible;
        }

        public void add_source (MediaSource source) {
            if (source.id == LocalSource.ID) return;
            if (_rows.has_key (key (source.id, null))) return;
            bool service = (source.features & SourceFeatures.ISOLATED) != 0;
            add_row (service ? _services : _sources, source.id, null, source.icon_name, source.title);
            update_sections ();
        }

        public void add_service_row (string id, string icon, string title) {
            if (_rows.has_key (key (id, null))) return;
            add_row (_services, id, null, icon, title);
            update_sections ();
        }

        public void remove_source (string source_id) {
            string k = key (source_id, null);
            var row = _rows[k];
            if (row == null) return;
            _rows.unset (k);
            var parent = row.get_parent () as Box;
            if (parent != null) parent.remove (row);
            update_sections ();
        }

        public bool has_source (string source_id) {
            return _rows.has_key (key (source_id, null));
        }

        private void update_sections () {
            _sources_label.visible = _sources.get_first_child () != null;
            _services_label.visible = _services.get_first_child () != null;
        }
    }
}
