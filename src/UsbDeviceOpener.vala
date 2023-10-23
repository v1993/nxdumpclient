/* UsbDeviceOpener.vala
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
	/**
	 * A helper class to keep track of device use in RAII manner.
	 */
	class UsbDeviceOpener: Object {
		public GUsb.Device dev { get; construct; default = null; }

		public UsbDeviceOpener(owned GUsb.Device dev_) throws Error {
			dev_.open();
			Object(dev: (owned)dev_);
		}

		~UsbDeviceOpener() {
			try {
				if (dev != null) {
					dev.close();
				}
			} catch(Error e) {
				critical("Failed to close a device: %s", e.message);
			}
		}
	}
}
