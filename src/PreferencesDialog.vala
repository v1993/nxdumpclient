/* PreferencesDialog.vala
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
// This is theoretically safe to have always on, but may hit bugs in portal backends.
private const bool FORCE_LIBPORTAL = false;

public enum NcaChecksumMode {
	COMPATIBLE,
	STRICT,
	NONE
}

namespace NXDumpClient {
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/PreferencesDialog.ui")]
	class PreferencesDialog: Adw.PreferencesDialog {
		[GtkChild]
		private unowned FileRow destination_directory;
		[GtkChild]
		private unowned Adw.SwitchRow flatten_output;
		[GtkChild]
		private unowned Adw.ComboRow nca_checksum_mode;
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
			// Cancel all pending operations once this dialog is closed to avoid references sticking around
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
				"nca-checksum-mode",
				nca_checksum_mode, "selected",
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

			// Special handling is needed on native backend too
			app.settings.bind(
				"autostart-enabled",
				autostart_enabled_row, "active",
				GET | NO_SENSITIVITY // TODO: account for setting writablitiy manually
			);

			#if WITH_LIBPORTAL
			if (FORCE_LIBPORTAL || Xdp.Portal.running_under_sandbox()) {
				autostart_enabled_row.notify["active"].connect(this.request_background);
			} else
			#endif
			{
				autostart_enabled_row.notify["active"].connect(this.set_autostart_native);
			}
		}

		[GtkCallback]
		private void reset_destination_directory() {
			new Application().settings.reset("dump-path");
		}

		#if WITH_LIBPORTAL
		private Xdp.Parent? make_xdp_parent() {
			var? toplevel = get_root() as Gtk.Window;
			if (toplevel == null) {
				// This is unexpected, but not critical
				warning("Failed to find root window for preferences dialog");
				return null;
			}

			return Xdp.parent_new_gtk(toplevel);
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
				autostart_cmd.add(BuildConfig.EXECUTABLE);
				autostart_cmd.add("--background");
				// D-Bus activation is not an option because of having to pass a flag
				var flags = need_autostart ? Xdp.BackgroundFlags.AUTOSTART : Xdp.BackgroundFlags.NONE;
				debug("Requesting background, autostart: %s", need_autostart.to_string());
				authorized = yield portal.request_background(
					make_xdp_parent(),
					C_("reason for background activity", "Dumping applications without interaction"),
					autostart_cmd,
					flags,
					cancellable
				);
			} catch(IOError.CANCELLED e) {
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
		#endif

		private async void set_autostart_native() {
			bool need_autostart = autostart_enabled_row.active;
			if (need_autostart == autostart_enabled) {
				return;
			}

			bool autostart_new_status = autostart_enabled;

			try {
				new_background_access_request();
				debug("Using native implementation to set autostart status to %s", need_autostart.to_string());
				var autostart_directory = File.new_build_filename(Environment.get_user_config_dir(), "autostart");
				var autostart_file = autostart_directory.get_child("org.v1993.NXDumpClient.desktop");

				if (need_autostart) {
					yield create_directory_with_parents_async(autostart_directory, cancellable);
					var contents = resources_lookup_data("/org/v1993/NXDumpClient/org.v1993.NXDumpClient.autostart.desktop", NONE);
					yield autostart_file.replace_contents_bytes_async(contents, null, false, NONE, cancellable, null);
				} else {
					try {
						yield autostart_file.delete_async(Priority.DEFAULT, cancellable);
					} catch(IOError.NOT_FOUND e) {
						// We're good
					}
				}

				autostart_new_status = need_autostart;
			} catch(IOError.CANCELLED e) {
			} catch(Error e) {
				var toast = new Adw.Toast.format(_("Failed to toggle autostart: %s"), e.message);
				add_toast((owned)toast);
			} finally {
				autostart_enabled = autostart_new_status;
				autostart_enabled_row.active = autostart_new_status;
			}
		}
	}
}
