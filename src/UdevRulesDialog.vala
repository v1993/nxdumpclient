/* UdevRulesDialog.vala
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

#if PROMPT_FOR_UDEV_RULES
namespace NXDumpClient {
	[GtkTemplate (ui = "/org/v1993/NXDumpClient/UdevRulesDialog.ui")]
	public class UdevRulesDialog: Adw.Window {
		protected string command_line_for_installation {
			owned get {
				var cmd = argv0;
				#if WITH_LIBPORTAL
				if (Xdp.Portal.running_under_flatpak()) {
					cmd = "flatpak run %s".printf(new Application().application_id);
				}
				#endif
				return "%s --print-udev-rules | sudo sh -c 'cat > %s/%s'".printf(cmd, UDEV_RULES_DIR, UDEV_RULES_FILENAME);
			}
		}

		[GtkCallback]
		void confirmed() {
			new Application().udev_rules_prompt_accepted();
			close();
		}
	}
}
#endif
