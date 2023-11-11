/* main.vala
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

internal string argv0;

int main(string[] args) {
	argv0 = args[0] ?? "nxdumpclient";

	Intl.setlocale();
	Intl.bindtextdomain(BuildCArgs.GETTEXT_PACKAGE, BuildConfig.LOCALE_DIR);
	Intl.bind_textdomain_codeset(BuildCArgs.GETTEXT_PACKAGE, "UTF-8");
	Intl.textdomain(BuildCArgs.GETTEXT_PACKAGE);

	var app = new NXDumpClient.Application();
	return app.run(args);
}
