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


// Debug option to use libportal even out of sandbox.
// This is theoretically safe to have always, but may hit bugs in portal backends.
const bool FORCE_LIBPORTAL = false;

namespace NXDumpClient {
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/PreferencesWindow.ui")]
	class PreferencesWindow: Adw.PreferencesWindow {
		[GtkChild]
		private unowned FileRow destination_directory;
		[GtkChild]
		private unowned Adw.SwitchRow flatten_output;
		[GtkChild]
		private unowned Adw.SwitchRow checksum_nca;
		[GtkChild]
		private unowned Adw.SwitchRow allow_background_row;

		#if WITH_LIBPORTAL
		// Note: unused if not running under sandbox
		protected bool allow_background { get; set; }
		#endif

		static construct {
			typeof(NXDumpClient.FileRow).ensure();
		}

		construct {
			var app = new Application();
			app.settings.bind_with_mapping(
				"dump-path",
				destination_directory, "file",
				DEFAULT,
				FileSettingUtils.get, FileSettingUtils.set, (void*)get_default_dump_path, null
			);

			app.settings.bind(
				"flatten-output",
				flatten_output, "active",
				DEFAULT
			);

			app.settings.bind(
				"checksum-nca",
				checksum_nca, "active",
				DEFAULT
			);

			#if WITH_LIBPORTAL
			if (FORCE_LIBPORTAL || Xdp.Portal.running_under_sandbox()) {
				app.settings.bind(
					"allow-background",
					this, "allow-background",
					DEFAULT
				);

				app.settings.bind(
					"allow-background",
					allow_background_row, "active",
					GET
				);

				allow_background_row.notify["active"].connect(this.background_changed);
			} else
			#endif
			{
				// No verification is needed; just bind directly
				app.settings.bind(
					"allow-background",
					allow_background_row, "active",
					DEFAULT
				);
			}
		}

		[GtkCallback]
		private void reset_destination_directory() {
			new Application().settings.reset("dump-path");
		}

		#if WITH_LIBPORTAL
		private async void background_changed() {
			var request_result = false;
			try {
				if (allow_background_row.active && !allow_background) {
					// TODO: split into a separate method when implementing autostart support
					var app = new Application();
					var? portal = app.portal;
					if (portal == null) {
						// It's hopeless
						return;
					}
					var parent = Xdp.parent_new_gtk(this);
					//var cmd = new GenericArray<unowned string>();
					request_result = yield portal.request_background(
						parent,
						C_("reason string for background activity", "Dumping applications in background"),
						null, // Binding issue, not our bug (fix PRed)
						NONE,
						app.cancellable
					);
				}
			} catch (IOError.CANCELLED e) {
			} catch (Error e) {
				warning("Error when requesting background permissions: %s", e.message);
			} finally {
				allow_background = request_result;
				// Check to avoid accidental recursion
				if (allow_background_row.active != request_result) {
					allow_background_row.active = request_result;
				}
			}
		}
		#endif
	}
}
