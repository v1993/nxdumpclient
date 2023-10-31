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

	internal class FileTransferInhibitor: Object {
		public static uint current_count { get; private set; }

		private uint cookie = 0;

		construct {
			cookie = new Application().inhibit(null, LOGOUT | SUSPEND, _("File transfer is in progres"));
			++current_count;
			debug("Inhibited, cookie: %u, active inhibitors: %u", cookie, current_count);
		}

		~FileTransferInhibitor() {
			var app = new Application();
			// May be false during app shutdown
			if (app.is_registered) {
				app.uninhibit(cookie);
			}
			--current_count;
			debug("Uninhibited, cookie: %u, active inhibitors: %u", cookie, current_count);
		}
	}

	[SingleInstance]
	public class Application: Adw.Application {
		// Settings object and corresponding fields
		public Settings settings { get; private set; }
		public File destination_directory { get; protected set; }
		public bool flatten_output { get; protected set; }
		public NcaChecksumMode nca_checksum_mode { get; protected set; }

		protected uint nca_checksum_mode_proxy { set { nca_checksum_mode = (NcaChecksumMode)value; } }

		private bool hold_background_reference_ = false;
		public bool hold_background_reference {
			get {
				return hold_background_reference_;
			}
			protected set {
				if (value && !hold_background_reference_) {
					hold();
				} else if (!value && hold_background_reference_) {
					release();
				}

				hold_background_reference_ = value;
			}
		}

		public ListStore device_list { get; private set; }
		public Cancellable cancellable { get; private set; default = new Cancellable(); }

		#if WITH_LIBPORTAL
		public Xdp.Portal? portal { get; private set; default = null; }
		#endif
		#if PROMPT_FOR_UDEV_RULES
		protected bool prompted_for_udev_rules { get; protected set; default = false; }

		public void udev_rules_prompt_accepted() {
			prompted_for_udev_rules = true;
		}
		#endif

		private bool background_bound = false;
		private UsbContext usb_ctx;
		private Window? main_window = null;

		private bool should_show_desktop_notification() {
			return !cancellable.is_cancelled() && (main_window == null || !main_window.is_active);
		}

		private bool should_show_toast() {
			return !cancellable.is_cancelled() && main_window != null;
		}

		public async bool query_app_exit() {
			var dialog = new Adw.MessageDialog(main_window, _("Confirm exit"), _("A file transfer is currently in progress.\nAre you sure you want to quit?")) {
				close_response = "cancel",
				default_response = "confirm",

			};
			dialog.add_response("cancel", C_("deny app exit", "Cancel"));
			dialog.add_response("confirm", C_("confirm app exit", "Confirm exit"));
			dialog.set_response_appearance("confirm", DESTRUCTIVE);
			var res = yield dialog.choose(cancellable);
			return res == "confirm";
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
			client.transfer_started.connect(this.file_transfer_started);
			client.transfer_got_empty_file.connect(this.file_transfer_complete);
			client.transfer_complete.connect(this.file_transfer_complete);
			client.transfer_failed.connect(this.file_transfer_failed);
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

		private async void file_transfer_started(UsbDeviceClient dev, File file, bool mass_transfer) {
			try {
				if (mass_transfer) {
					return;
				}

				if (should_show_desktop_notification()) {
					var notif = new Notification(_("File transfer started"));
					var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, cancellable);
					notif.set_body(info.get_display_name());
					notif.set_category("device");
					send_notification(@"nxdc-file-$(file.get_uri())", notif);
				}
			} catch(IOError.CANCELLED e) {
			} catch(Error e) {
				warning("Error sending notification: %s", e.message);
			}
		}

		private async void file_transfer_complete(UsbDeviceClient dev, File file, bool mass_transfer) {
			try {
				if (mass_transfer) {
					return;
				}

				var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, cancellable);
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
			} catch(IOError.CANCELLED e) {
			} catch(Error e) {
				warning("Error sending notification: %s", e.message);
			}
		}

		private async void file_transfer_failed(UsbDeviceClient dev, File file, bool cancelled) {
			try {
				var info = file.query_info(FileAttribute.STANDARD_DISPLAY_NAME, NONE, cancellable);
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

		construct {
			application_id = "org.v1993.NXDumpClient";
			flags = HANDLES_COMMAND_LINE;

			OptionEntry[] options = {
				{ "background", '\0', NONE, NONE, null, _("Launch without a visible window if allowed to in settings, exit otherwise") },
				{ "print-udev-rules", '\0', NONE, NONE, null, _("Print udev rules required for USB access and exit") },
				{ "version", 'v', NONE, NONE, null, _("Print application version and exit") },
				{null}
			};

			add_main_option_entries(options);
			set_option_context_summary(_("Client for dumping over USB with nxdumptool."));

			ActionEntry[] action_entries = {
				// In-app only
				{ "about", this.on_about_action },
				{ "preferences", this.on_preferences_action },
				{ "quit", this.on_quit_with_confirmation_action },

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
				NO_SENSITIVITY | GET,
				FileSettingUtils.get, FileSettingUtils.set, (void*)get_default_dump_path, null
			);

			settings.bind("flatten-output",
				this, "flatten-output",
				NO_SENSITIVITY | GET
			);

			settings.bind("nca-checksum-mode",
				this, "nca-checksum-mode-proxy",
				NO_SENSITIVITY | GET
			);

			// allow-background is bound in bind_background.
			// This is done to avoid making one-shot invocations (mainly actions)
			// from sticking around.

			#if PROMPT_FOR_UDEV_RULES
			settings.bind("prompted-for-udev-rules",
				this, "prompted-for-udev-rules",
				NO_SENSITIVITY | GET | SET
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

		// Call only if you're fine with current instance running in background if allowed so by settings
		private void bind_background() {
			if (background_bound) {
				return;
			}

			settings.bind("allow-background",
				this, "hold-background-reference",
				NO_SENSITIVITY
			);

			background_bound = true;
		}

		private void initialize_usb() {
			if (usb_ctx != null) {
				return;
			}

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

		public override int command_line(ApplicationCommandLine command_line) {
			debug("command_line() invoked, is_remote: %s", command_line.is_remote.to_string());
			if (command_line.get_options_dict().contains("background")) {
				if (command_line.is_remote) {
					command_line.print("Ignoring background launch - primary instance already running\n");
					return 0;
				}

				// This will acquire a reference if enabled in settings
				bind_background();
				if (!hold_background_reference) {
					// Background mode disabled in settings - just exit
					return 0;
				}

				initialize_usb();
				return 0;
			} else {
				activate();
				return 0;
			}
		}

		public override void activate() {
			base.activate();
			bind_background();
			initialize_usb();

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

		public override void shutdown() {
			// Cancel pending operations
			cancellable.cancel();
			// Let async handlers that registered themselves at the previous step run
			MainContext.default().iteration(false);
			base.shutdown();
		}

		private void on_about_action() {
			var about = new Adw.AboutWindow.from_appdata("/org/v1993/NXDumpClient/appdata.xml", NXDC_VERSION) {
				transient_for = main_window,
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
				transient_for = main_window
			};

			preferences.present();
		}

		private void on_show_file_action(SimpleAction action, Variant? param)
		requires(param != null && param.is_of_type(VariantType.STRING))
		{
			show_file.begin(File.new_for_uri(param.get_string()));
		}

		private void on_quit_with_confirmation_action() {
			// Do not test if background is enabled - app exit bypasses that
			if (FileTransferInhibitor.current_count == 0) {
				quit();
			} else {
				quit_with_confirmation.begin();
			}
		}

		private async void quit_with_confirmation() {
			var res = yield query_app_exit();
			if (res) {
				quit();
			}
		}

		private async void show_file(File file) {
			hold(); // Ensure that we won't exit if invoked without activation
			try {
				var launcher = new Gtk.FileLauncher(file);
				yield launcher.open_containing_folder(main_window, cancellable);
			} catch(IOError.CANCELLED e) {
			} catch(Error e) {
				warning("Failed to show file in directory: %s", e.message);
			} finally {
				release();
			}
		}
	}
}
