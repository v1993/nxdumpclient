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

extern const string NXDC_EXECUTABLE;

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
		[GtkChild]
		private unowned Adw.SwitchRow autostart_enabled_row;

		private Cancellable? cancellable = null;

		public bool allow_background { get; protected set; }
		public bool autostart_enabled { get; protected set; }

		static construct {
			typeof(NXDumpClient.FileRow).ensure();
		}

		private void on_unrealized() {
			cancellable.cancel();
		}

		private void background_changed() {
			if (!allow_background) {
				// Ensure this since settings binding seem to miss it in some cases
				autostart_enabled_row.active = false;
				autostart_enabled = false;
			}
		}

		// Cancel previous requests; get a new cancellable for us
		private void new_background_access_request() {
			((!)cancellable).cancel();
			cancellable = new Cancellable();
			// Old cancellable is disconnected automatically
			new Application().cancellable.connect(cancellable.cancel);
		}

		construct {
			var app = new Application();
			cancellable = new Cancellable();
			app.cancellable.connect(cancellable.cancel);
			// Cancel all pending operations once this window is closed to avoid references sticking around
			((Gtk.Widget)this).unrealize.connect(this.on_unrealized);

			notify["allow-background"].connect(this.background_changed);

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

			app.settings.bind(
				"allow-background",
				this, "allow-background",
				DEFAULT
			);

			#if WITH_LIBPORTAL
			if (FORCE_LIBPORTAL || Xdp.Portal.running_under_sandbox()) {
				app.settings.bind(
					"allow-background",
					allow_background_row, "active",
					GET
				);

				allow_background_row.notify["active"].connect(this.request_background);
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

			app.settings.bind(
				"autostart-enabled",
				this, "autostart-enabled",
				DEFAULT
			);

			// Special handling is always required for autostart
			app.settings.bind(
				"autostart-enabled",
				autostart_enabled_row, "active",
				GET | NO_SENSITIVITY
			);
			// TODO: account for setting writablitiy
			autostart_enabled_row.notify["active"].connect(this.autostart_toggle_changed);
		}

		[GtkCallback]
		private void reset_destination_directory() {
			new Application().settings.reset("dump-path");
		}

		#if WITH_LIBPORTAL
		private void autostart_toggle_changed() {
			request_background.begin();
		}

		private async void request_background() {
			/*
			 * The following cases require us to make a request:
			 * !allow_background -> allow_background -- always (enable background)
			 * !autostart_enabled -> autostart_enabled -- always (enable autostart)
			 * autostart_enabled -> !autostart_enabled -- always (disable autostart)
			 */
			bool should_request = false;
			bool need_autostart = autostart_enabled_row.active;
			should_request |= allow_background_row.active && !allow_background;
			should_request |= autostart_enabled_row.active != autostart_enabled;

			if (!should_request) {
				debug("Not querying for new background settings");
				allow_background = allow_background_row.active;
				autostart_enabled = autostart_enabled_row.active;
				return;
			}

			bool authorized = false;

			try {
				new_background_access_request();
				var? portal = new Application().portal;
				if (portal == null) {
					// It's hopeless
					return;
				}

				var autostart_cmd = new GenericArray<unowned string>(2);
				autostart_cmd.add(NXDC_EXECUTABLE);
				autostart_cmd.add("--background");
				// D-Bus activation is not an option because of having to pass a flag
				var flags = need_autostart ? Xdp.BackgroundFlags.AUTOSTART : Xdp.BackgroundFlags.NONE;
				debug("Requesting background, autostart: %s", need_autostart.to_string());
				authorized = yield portal.request_background(
					Xdp.parent_new_gtk(this),
					C_("reason for background activity", "Dumping applications without interaction"),
					autostart_cmd,
					flags,
					cancellable
				);
			} catch(Error e) {
				var toast = new Adw.Toast.format(_("Permission request failed: %s"), e.message);
				add_toast((owned)toast);
			} finally {
				debug("Background request result: %s", authorized.to_string());
				var background_result = allow_background_row.active && authorized;
				var autostart_result = need_autostart && authorized;
				allow_background = background_result;
				autostart_enabled = autostart_result;
				allow_background_row.active = background_result;
				autostart_enabled_row.active = autostart_result;
			}
		}
		#else
		private void autostart_toggle_changed() {
			if (autostart_enabled_row.active) {
				critical("Autostart without libportal unimplemented!");
				autostart_enabled_row.active = false;
			}
		}
		#endif
	}
}
