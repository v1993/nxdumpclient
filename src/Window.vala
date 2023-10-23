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

		protected Gtk.SelectionModel devices_model { get; set; }

		public Window(Gtk.Application app) {
			Object(
				application: app
			);
		}

		ulong content_selector_signal = 0;

		private static void select_child_cb(ListStore store, uint position, uint removed, uint added, Window win) {
			win.select_child(store);
		}

		private void select_child(ListStore store) {
			content_selector.set_visible_child_name(store.n_items == 0 ? "placeholder" : "devlist");
		}

		construct {
			unowned var devlist = new Application().device_list;
			content_selector_signal = Signal.connect(devlist, "items-changed", (Callback)((void*)select_child_cb), this);
			select_child(devlist);
			devices_model = new Gtk.NoSelection(devlist);
		}

		~Window() {
			new Application().device_list.disconnect(content_selector_signal);
		}

		public void show_toast(owned Adw.Toast toast) {
			toast_overlay.add_toast((owned)toast);
		}

		[GtkCallback]
		void setup_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			litem.child = new DeviceStatusRow();
		}

		[GtkCallback]
		void teardown_element(Gtk.SignalListItemFactory factory, Object o) {
		}

		[GtkCallback]
		void bind_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			var child = (DeviceStatusRow)litem.child;
			child.bind((UsbDeviceClient)litem.item);
		}

		[GtkCallback]
		void unbind_element(Gtk.SignalListItemFactory factory, Object o) {
			var litem = (Gtk.ListItem)o;
			var child = (DeviceStatusRow)litem.child;
			child.unbind();
		}
	}
}
