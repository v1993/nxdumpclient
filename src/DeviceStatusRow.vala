/* DeviceStatusRow.vala
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
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/DeviceStatusRow.ui")]
	class DeviceStatusRow: Adw.Bin {
		protected UsbDeviceClient? device { get; set; default = null; }

		private ulong[] device_signals = {};

		public void bind(UsbDeviceClient dev_) {
			device = dev_;
			update_status();
			device_signals += Signal.connect(device, "notify::status", (Callback)((void*)on_status_changed), this);
			update_connection_speed(); // Does not need to be tracked
			update_version();
			device_signals += Signal.connect(device, "notify::version-string", (Callback)((void*)on_version_changed), this);
			setup_progress();
			device_signals += Signal.connect(device, "transfer-started", (Callback)((void*)transfer_started_cb), this);
			device_signals += Signal.connect(device, "transfer-next-inner-file", (Callback)((void*)update_filenames_cb), this);
			device_signals += Signal.connect(device, "transfer-progress", (Callback)((void*)update_progress_cb), this);
			device_signals += Signal.connect(device, "transfer-complete", (Callback)((void*)transfer_complete_cb), this);
			device_signals += Signal.connect(device, "transfer-failed", (Callback)((void*)transfer_failed_cb), this);
		}

		public void unbind() {
			unregister_sginals();
			device = null;
		}

		~DeviceStatusRow() {
			unregister_sginals();
		}

		private void unregister_sginals() {
			foreach(var handler_id in device_signals) {
				device.disconnect(handler_id);
			}

			device_signals = {};
		}

		private static void on_status_changed(UsbDeviceClient client, ParamSpec pspec, DeviceStatusRow row) {
			row.update_status();
		}

		private static void on_version_changed(UsbDeviceClient client, ParamSpec pspec, DeviceStatusRow row) {
			row.update_version();
		}

		protected string status_text { get; set; default = ""; }
		protected string connection_speed_text { get; set; default = ""; }
		protected string version_text { get; set; default = ""; }

		protected double transfer_fraction { get; set; default = 0.0; }
		protected string transfer_text { get; set; default = ""; }
		protected string file_name { get; set; default = ""; }
		protected string file_name_inner { get; set; default = ""; }

		[GtkChild]
		unowned Gtk.Box progress_box;

		private void update_status()
		requires(device != null)
		{
			switch (device.status) {
				case UNINITIALIZED:
					status_text = C_("status", "Uninitialized");
					break;
				case CONNECTED:
					status_text = C_("status", "Connected");
					break;
				case TRANSFER:
					status_text = C_("status", "Transferring file");
					break;
				case FATAL_ERROR:
					status_text = "<span color=\"red\">" + C_("status", "Fatal error") + "</span>";
					break;
			}

			progress_box.sensitive = (device.status == TRANSFER);
		}

		private void setup_progress()
		requires(device != null)
		{
			if (device.status != TRANSFER) {
				reset_transfer_view();
			} else {
				update_filenames();
				update_progress();
			}
		}

		private static void update_progress_cb(UsbDeviceClient client, DeviceStatusRow row) {
			row.update_progress();
		}

		private void update_progress()
		requires(device != null)
		{
			transfer_fraction = ((double)device.transfer_current_bytes) / ((double)device.transfer_total_bytes);
			transfer_text = C_("file transfer progress", "%s / %s").printf(
				format_size(device.transfer_current_bytes),
				format_size(device.transfer_total_bytes)
			);
		}

		private static void transfer_started_cb(UsbDeviceClient client, File file, bool mass_transfer, DeviceStatusRow row) {
			row.update_filenames();
		}

		private static void update_filenames_cb(UsbDeviceClient client, DeviceStatusRow row) {
			row.update_filenames();
		}

		private void update_filenames()
		requires(device != null)
		{
			file_name = device.transfer_file_name;
			file_name_inner = device.transfer_file_name_inner;
		}

		private static void transfer_failed_cb(UsbDeviceClient client, File file, bool cancelled, DeviceStatusRow row) {
			row.reset_transfer_view();
		}

		private static void transfer_complete_cb(UsbDeviceClient client, File file, bool mass_transfer, DeviceStatusRow row) {
			row.reset_transfer_view();
		}

		private void reset_transfer_view() {
			transfer_fraction = 0.0;
			transfer_text = "";
			file_name = "";
			file_name_inner = "";
		}

		private void update_connection_speed()
		requires(device != null)
		{
			switch (device.max_packet_size) {
				case 64:
					connection_speed_text = _("USB 1.1");
					break;
				case 512:
					connection_speed_text = _("USB 2.0");
					break;
				case 1024:
					connection_speed_text = _("USB 3.0");
					break;
				default:
					connection_speed_text = C_("speed string", "N/A");
					break;
			}
		}

		private void update_version()
		requires(device != null)
		{
			version_text = device.version_string ?? C_("version string", "N/A");
		}
	}
}
