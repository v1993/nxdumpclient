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

		public void show_error(string desc, string message) {
			if (main_window != null) {
				var toast = new Adw.Toast.format("<span color=\"red\">%s</span>: %s", desc, message) {
					timeout = 10,
					priority = HIGH
				};
				main_window.show_toast((owned)toast);
			} else {
				var notif = new Notification(desc);
				notif.set_body(message);
				notif.set_category("device.error");
				notif.set_priority(HIGH);
				// FIXME: icon does not show. Is it on KDE or me?
				notif.set_icon(new ThemedIcon("dialog-error"));
				send_notification(null, notif);
			}
		}

        construct {
			application_id = "org.v1993.NXDumpClient";
			flags = DEFAULT_FLAGS;

			OptionEntry[] options = {
				{ "version", 'v', NONE, NONE, null, _("Print application version and exit") },
				{null}
			};

			add_main_option_entries(options);
			set_option_context_summary(_("Client for dumping over USB with nxdumptool."));

            ActionEntry[] action_entries = {
                { "about", this.on_about_action },
                { "preferences", this.on_preferences_action },
                { "quit", this.quit }
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

			settings.bind_with_mapping("flatten-output",
				this, "flatten-output",
				DEFAULT,
				null, null, null, null // A binding issue
			);

			settings.bind_with_mapping("checksum-nca",
				this, "checksum-nca",
				DEFAULT,
				null, null, null, null // A binding issue
			);

			try {
				usb_ctx = new UsbContext();

				// Allow window to show up first
				Idle.add(() => {
					usb_ctx.enumerate();
					return Source.REMOVE;
				}, Priority.DEFAULT_IDLE);
			} catch(Error e) {
				printerr(_("Failed to initialize USB context: %s\n"), e.message);
				Process.exit(1);
			}

			device_list = new ListStore(typeof(UsbDeviceClient));
		}

		private static void unset_main_window(Window win, Application app) {
			app.main_window = null;
		}

        public override void activate() {
        	base.activate();
        	if (main_window == null) {
				main_window = new Window(this);
				// Syntax sugar kept failing me. This works flawlessly.
				main_window.connect("signal::unrealize", unset_main_window, this, null);
            }
            main_window.present();
        }

        private void on_about_action() {
            string[] developers = { "v19930312" };
            var about = new Adw.AboutWindow() {
                transient_for = this.active_window,
                application_name = "NX Dump Client",
                application_icon = "org.v1993.NXDumpClient",
                developer_name = "v19930312",
                version = NXDC_VERSION,
                developers = developers,
                copyright = "© 2023 v19930312",
            };

            about.present();
        }

        private void on_preferences_action() {
            var preferences = new PreferencesWindow() {
				transient_for = this.active_window
			};

			preferences.present();
        }
    }
}
