/* PreferencesWindow.vala
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
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/PreferencesWindow.ui")]
	class PreferencesWindow: Adw.PreferencesWindow {
		[GtkChild]
		private unowned FileRow destination_directory;
		[GtkChild]
		private unowned Adw.SwitchRow flatten_output;
		[GtkChild]
		private unowned Adw.SwitchRow checksum_nca;

		static construct {
			typeof(NXDumpClient.FileRow).ensure();
		}

		construct {
			new Application().settings.bind_with_mapping(
				"dump-path",
				destination_directory, "file",
				DEFAULT,
				FileSettingUtils.get, FileSettingUtils.set, (void*)get_default_dump_path, null
			);

			new Application().settings.bind(
				"flatten-output",
				flatten_output, "active",
				DEFAULT
			);

			new Application().settings.bind(
				"checksum-nca",
				checksum_nca, "active",
				DEFAULT
			);
		}

		[GtkCallback]
		private void reset_destination_directory() {
			new Application().settings.reset("dump-path");
		}
	}
}
