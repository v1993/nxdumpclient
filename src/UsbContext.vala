/* UsbContext.vala
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
	class UsbContext: GUsb.Context {
		private const uint16 TARGET_VID = 0x057E;
		private const uint16 TARGET_PID = 0x3000;
		private const string TARGET_MANUFACTURER = "DarkMatterCore";
		private const string TARGET_PRODUCT = "nxdumptool";
		private const string TARGET_PRODUCT_DEV = "nxdt_rw_poc"; // TODO: remove once rewrite is un-re-branded

		public UsbContext() throws Error {
			Object();
			init();
		}

		public override void device_added(GUsb.Device dev) {
			try {
				if (dev.get_vid() != TARGET_VID || dev.get_pid() != TARGET_PID) {
					return;
				}

				var opener = new UsbDeviceOpener(dev);
				var manufacturer = opener.dev.get_string_descriptor(dev.get_manufacturer_index());
				var product = opener.dev.get_string_descriptor(dev.get_product_index());

				if (manufacturer != TARGET_MANUFACTURER || (product != TARGET_PRODUCT && product != TARGET_PRODUCT_DEV)) {
					return;
				}

				debug("Detected a suitable device! Product string: %s", dev.get_string_descriptor(dev.get_product_index()));
				new Application().device_list.append(new UsbDeviceClient((owned)opener));
			} catch(GUsb.DeviceError.NO_DEVICE e) {
				// Not really a problem - device was disconnected during setup
			} catch(Error e) {
				report_error(_("Error handling a new device"), e.message);
			}
		}

		public override void device_removed(GUsb.Device dev) {
			var devlist = new Application().device_list;
			for(uint i = 0; i < devlist.n_items;) {
				var list_dev = (UsbDeviceClient) devlist.get_object(i);
				if (dev == list_dev.dev) {
					devlist.remove(i);
				} else {
					++i;
				}
			}
		}
	}
}
