/* FileRow.vala
 *
 * Copyright 2023 v1993 <v19930312@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private bool transform_file_to_path(Binding bin, Value from, out Value to) {
	unowned var? file = from.get_object() as File;
	to = Value(Type.STRING);
	if (file != null) {
		to.set_string(file.get_parse_name());
	} else {
		to.set_string(_("(unset)"));
	}
	return true;
}

private bool transform_select_directory_to_icon(Binding bin, Value from, out Value to) {
	var is_directory = from.get_boolean();
	to = Value(Type.STRING);
	to.set_string(is_directory ? "folder-open-symbolic" : "document-open-symbolic");
	return true;
}

private bool transform_select_directory_to_tooltip(Binding bin, Value from, out Value to) {
	var is_directory = from.get_boolean();
	to = Value(Type.STRING);
	to.set_string(is_directory ? _("Select directory") : _("Select file"));
	return true;
}

namespace NXDumpClient {
    [GtkTemplate (ui = "/org/v1993/NXDumpClient/widgets/FileRow.ui")]
    public class FileRow: Adw.ActionRow {
		public File? file { get; set; default = null; }
		public bool select_directory { get; set; default = false; }
		public bool allow_reset { get; set; default = false; }
		public Gtk.FileDialog file_dialog { get; set; default = new Gtk.FileDialog(); }

		public Cancellable? cancellable { get; set; default = null; }

		public signal void reset();

		[GtkChild]
		private unowned Gtk.Button button;

		// See https://gitlab.gnome.org/GNOME/vala/-/issues/1493
		[GtkCallback]
		private void emit_reset() {
			reset.emit();
		}

		construct {
			bind_property("file", this, "subtitle", SYNC_CREATE, transform_file_to_path, null);
			bind_property("select-directory", button, "icon-name", SYNC_CREATE, transform_select_directory_to_icon, null);
			bind_property("select-directory", button, "tooltip-text", SYNC_CREATE, transform_select_directory_to_tooltip, null);
		}

		[GtkCallback]
		private async void select_file() {
			try {
				File? new_file;
				var root = get_root() as Gtk.Window;
				if (select_directory) {
					new_file = yield file_dialog.select_folder(root, cancellable);
				} else {
					new_file = yield file_dialog.open(root, cancellable);
				}

				if (new_file != null) {
					file = new_file;
				}
			} catch(IOError.CANCELLED e) {
			} catch(Gtk.DialogError.CANCELLED e) {
			} catch(Gtk.DialogError.DISMISSED e) {
			} catch(Error e) {
				critical("Unhandled error: %s", e.message);
			}
		}
	}
}
