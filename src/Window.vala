/* Window.vala
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

namespace NXDumpClient {
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/Window.ui")]
	public class Window: Adw.ApplicationWindow {
		[GtkChild]
		private unowned Adw.ToastOverlay toast_overlay;
		[GtkChild]
		private unowned Gtk.Stack content_selector;

		public Gtk.SelectionModel devices_model { get; construct; }

		private bool close_confirmed = false;

		public Window(Gtk.Application app) {
			Object(
				application: app
			);
		}

		~Window() {
			debug("Window finalized");
		}

		private void select_child(ListModel model, uint position, uint removed, uint added)
		requires(model is ListStore)
		{
			content_selector.set_visible_child_name(((ListStore)model).n_items == 0 ? "placeholder" : "devlist");
		}

		construct {
			unowned var devlist = new Application().device_list;
			devlist.items_changed.connect(this.select_child);
			select_child(devlist, 0, 0, 0);
			devices_model = new Gtk.NoSelection(devlist);
		}

		public void show_toast(owned Adw.Toast toast) {
			toast_overlay.add_toast((owned)toast);
		}

		[GtkCallback]
		private bool on_close_request() {
			// Return true to NOT close, false to CLOSE
			if (close_confirmed) {
				return false; // Close, queried the user and was allowed to
			}

			if (FileTransferInhibitor.current_count == 0) {
				return false; // Close, nothing is running in background
			}

			var app = new Application();
			if (app.hold_background_reference) {
				return false; // Close, application will keep running
			}

			query_for_close.begin();
			return true; // Do not close; present a query
		}

		private async void query_for_close() {
			var result = yield new Application().query_app_exit();
			if (result) {
				close_confirmed = true;
				close();
				close_confirmed = false;
			}
		}

		[GtkCallback]
		private void setup_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			litem.child = new DeviceStatusRow();
		}

		[GtkCallback]
		private void teardown_element(Gtk.SignalListItemFactory factory, Object o) {
		}

		[GtkCallback]
		private void bind_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			var child = (DeviceStatusRow)litem.child;
			child.bind((UsbDeviceClient)litem.item);
		}

		[GtkCallback]
		private void unbind_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			var child = (DeviceStatusRow)litem.child;
			child.unbind();
		}
	}
}
