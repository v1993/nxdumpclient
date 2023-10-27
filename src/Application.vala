/* Application.vala
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

extern const string NXDC_VERSION;
extern const string NXDC_ICONS_PATH;

namespace NXDumpClient {
	/// A convenience method to show errors to user
	internal void report_error(string desc, string message) {
		new Application().show_error(desc, message);
	}

	[SingleInstance]
	public class Application: Adw.Application {
		public Settings settings { get; private set; }
		public File destination_directory { get; protected set; }
		public bool flatten_output { get; protected set; }
		public bool checksum_nca { get; protected set; }
		public ListStore device_list { get; private set; }

		private UsbContext usb_ctx;
		private Window? main_window = null;

		#if WITH_LIBPORTAL
		public Xdp.Portal? portal { get; private set; default = null; }
		#endif
		#if PROMPT_FOR_UDEV_RULES
		protected bool prompted_for_udev_rules { get; protected set; default = false; }

		public void udev_rules_prompt_accepted() {
			prompted_for_udev_rules = true;
		}
		#endif

		private bool should_show_desktop_notification() {
			return main_window == null || !main_window.is_active;
		}

		private bool should_show_toast() {
			return main_window != null;
		}

		public void show_error(string desc, string message) {
			if (should_show_toast()) {
				var toast = new Adw.Toast.format("<span color=\"red\">%s</span>: %s", desc, message) {
					timeout = 5,
					priority = HIGH
				};
				main_window.show_toast((owned)toast);
			}

			if (should_show_desktop_notification()) {
				var notif = new Notification(desc);
				notif.set_body(message);
				notif.set_category("device.error");
				notif.set_priority(HIGH);
				notif.set_icon(new ThemedIcon("dialog-error"));
				send_notification(null, notif);
			}
		}

		internal void device_added(UsbDeviceClient client) {
			client.transfer_started.connect(this.on_file_transfer_started);
			client.transfer_complete.connect(this.on_file_transfer_complete);
			client.transfer_failed.connect(this.on_file_transfer_failed);
			if (should_show_desktop_notification()) {
				var notif = new Notification(_( "nxdumptool device connected"));
				notif.set_category("device.added");
				send_notification(@"nxdc-device-$(client.dev.get_bus())-$(client.dev.get_address())", notif);
			}
		}

		internal void device_removed(GUsb.Device dev) {
			if (should_show_desktop_notification()) {
				var notif = new Notification(_("nxdumptool device disconnected"));
				notif.set_category("device.removed");
				send_notification(@"nxdc-device-$(dev.get_bus())-$(dev.get_address())", notif);
			}
		}

		private void on_file_transfer_started(UsbDeviceClient dev, File file, bool mass_transfer) {
			file_transfer_started.begin(file, mass_transfer);
		}

		private async void file_transfer_started(File file, bool mass_transfer) {
			try {
				if (mass_transfer) {
					return;
				}

				if (should_show_desktop_notification()) {
					var notif = new Notification(_("File transfer started"));
					var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, null); // TODO: cancellable
					notif.set_body(info.get_display_name());
					notif.set_category("device");
					send_notification(@"nxdc-file-$(file.get_uri())", notif);
				}
			} catch(Error e) {
				warning("Error sending notification: %s", e.message);
			}
		}

		private void on_file_transfer_complete(UsbDeviceClient dev, File file, bool mass_transfer) {
			file_transfer_complete.begin(file, mass_transfer);
		}

		private async void file_transfer_complete(File file, bool mass_transfer) {
			try {
				if (mass_transfer) {
					return;
				}

				var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, null); // TODO: cancellable
				var fname = info.get_display_name();

				if (should_show_desktop_notification()) {
					var notif = new Notification(_("File transfer complete"));
					notif.set_body(fname);
					notif.set_category("device");
					notif.add_button_with_target_value(_("Show in folder"), "app.show-file", new Variant.take_string(file.get_uri()));
					send_notification(@"nxdc-file-$(file.get_uri())", notif);
				}

				if (should_show_toast()) {
					var toast = new Adw.Toast.format(_("Transfer of file “%s” complete"), fname) {
						button_label = _("Show in folder"),
						action_name = "app.show-file",
						action_target = new Variant.take_string(file.get_uri()),
					};
					main_window.show_toast((owned)toast);
				}
			} catch(Error e) {
				warning("Error sending notification: %s", e.message);
			}
		}

		private void on_file_transfer_failed(UsbDeviceClient dev, File file, bool cancelled) {
			file_transfer_failed.begin(file, cancelled);
		}

		private async void file_transfer_failed(File file, bool cancelled) {
			try {
				var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, null); // TODO: cancellable
				var fname = info.get_display_name();

				if (should_show_desktop_notification()) {
					var notif = new Notification(cancelled ? _("File transfer canceled") : _("File transfer failed"));
					notif.set_body(fname);
					notif.set_category("device");
					send_notification(@"nxdc-file-$(file.get_uri())", notif);
				}

				if (should_show_toast()) {
					var toast = new Adw.Toast.format(cancelled ? _("Transfer of file “%s” canceled") : _("Transfer of file “%s” failed"), fname);
					main_window.show_toast((owned)toast);
				}
			} catch(Error e) {
				warning("Error sending notification: %s", e.message);
			}
		}

		// TODO: add "on_transfer_cancelled"

		construct {
			application_id = "org.v1993.NXDumpClient";
			flags = DEFAULT_FLAGS;

			OptionEntry[] options = {
				{ "version", 'v', NONE, NONE, null, _("Print application version and exit") },
				{ "print-udev-rules", '\0', NONE, NONE, null, _("Print udev rules required for USB access and exit") },
				{null}
			};

			add_main_option_entries(options);
			set_option_context_summary(_("Client for dumping over USB with nxdumptool."));

			ActionEntry[] action_entries = {
				// In-app only
				{ "about", this.on_about_action },
				{ "preferences", this.on_preferences_action },
				{ "quit", this.quit },

				// May be invoked externally (e.g. from a notification)
				{ "show-file", this.on_show_file_action, "s" }
			};

			add_action_entries(action_entries, this);
			set_accels_for_action("app.preferences", {"<primary>p"});
			set_accels_for_action("app.quit", {"<primary>q"});
		}

		public override int handle_local_options(VariantDict opt) {
			if (opt.lookup("version", "b", null)) {
				print("nxdumpclient %s\n", NXDC_VERSION);
				return 0;
			}

			if (opt.lookup("print-udev-rules", "b", null)) {
				try {
					var contents = resources_lookup_data("/org/v1993/NXDumpClient/" + UDEV_RULES_FILENAME, NONE);
					//var rule_path = Path.build_filename(UDEV_RULES_DIR, UDEV_RULES_FILENAME);
					print("%s", (string)contents.get_data());
				} catch(Error e) {
					printerr("Failed to print udev rules: %s\n", e.message);
					return 1;
				}
				return 0;
			}

			return -1;
		}

		public override void startup() {
			base.startup();

			settings = new GLib.Settings(application_id);
			settings.bind_with_mapping("dump-path",
				this, "destination-directory",
				DEFAULT,
				FileSettingUtils.get, FileSettingUtils.set, (void*)get_default_dump_path, null
			);

			settings.bind("flatten-output",
				this, "flatten-output",
				DEFAULT
			);

			settings.bind("checksum-nca",
				this, "checksum-nca",
				DEFAULT
			);

			#if PROMPT_FOR_UDEV_RULES
			settings.bind("prompted-for-udev-rules",
				this, "prompted-for-udev-rules",
				DEFAULT
			);
			#endif

			device_list = new ListStore(typeof(UsbDeviceClient));

			#if WITH_LIBPORTAL
			try {
				portal = new Xdp.Portal.initable_new();
			} catch(Error e) {
				warning("Failed to initialize libportal: %s", e.message);
			}

			if (Xdp.Portal.running_under_flatpak()) {
				// Fix About dialog icon
				debug("Adding to icons path: %s", NXDC_ICONS_PATH);
				Gtk.IconTheme.get_for_display(Gdk.Display.get_default()).add_search_path(NXDC_ICONS_PATH);
			}
			#endif
		}

		private void unset_main_window(Gtk.Widget win) {
			// Catch nasty typing problems
			assert(win is Window && (Window)win == main_window);
			main_window = null;
		}

		public override void activate() {
			base.activate();
			if (usb_ctx == null) {
				try {
					usb_ctx = new UsbContext();

					// Allow window to show up first
					Idle.add_once(() => {
						usb_ctx.enumerate();
					});
				} catch(Error e) {
					printerr(_("Failed to initialize USB context: %s\n"), e.message);
					Process.exit(1);
				}
			}

			if (main_window == null) {
				main_window = new Window(this);
				// Typing hiccups prevent syntax sugar from doing its job nicely here.
				((Gtk.Widget)main_window).unrealize.connect(this.unset_main_window);
			}
			main_window.present();
 			#if PROMPT_FOR_UDEV_RULES
 			if (!prompted_for_udev_rules) {
				var udev_dialog = new UdevRulesDialog() {
					transient_for = main_window
				};
				udev_dialog.present();
			}
 			#endif
		}

		private void on_about_action() {
			var about = new Adw.AboutWindow.from_appdata("/org/v1993/NXDumpClient/appdata.xml", NXDC_VERSION) {
				transient_for = this.active_window,
				translator_credits = _("translator-credits"),
				developers = {
					"v19930312"
				},
				copyright = "© 2023 v19930312"
			};

 			about.add_credit_section(C_("credits section header", "nxdumptool team"),
 				{
					"DarkMatterCore",
					"Whovian9369",
					"shchmue"
				}
 			);

			about.present();
		}

		private void on_preferences_action() {
			var preferences = new PreferencesWindow() {
				transient_for = this.active_window
			};

			preferences.present();
		}

		private void on_show_file_action(SimpleAction action, Variant? param)
		requires(param != null && param.is_of_type(VariantType.STRING))
		{
			show_file.begin(File.new_for_uri(param.get_string()));
		}

		private async void show_file(File file) {
			hold(); // Ensure that we won't exit if invoked without activation
			try {
				var launcher = new Gtk.FileLauncher(file);
				yield launcher.open_containing_folder(main_window, null); // TODO: pass cancellable
			} catch(Error e) {
				warning("Failed to show file in directory: %s", e.message);
			} finally {
				release();
			}
		}
	}
}
