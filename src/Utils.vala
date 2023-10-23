/* Utils.vala
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
	string get_default_dump_path() {
		return Environment.get_user_special_dir(DOWNLOAD) ?? Environment.get_home_dir();
	}

	/// Note: does not throw if target already exists
	async void create_directory_with_parents_async(File file, Cancellable? cancellable = null) throws Error {
		var to_create = new File[0];
		var? current_target = file;
		while(current_target != null) {
			try {
				yield current_target.make_directory_async(Priority.DEFAULT, cancellable);
			} catch(IOError.NOT_FOUND e) {
				to_create += current_target;
				current_target = current_target.get_parent();
				continue;
			} catch(IOError.EXISTS e) {
				break;
			}
			break;
		}

		for (int i = to_create.length - 1; i >= 0; --i) {
			try {
				yield to_create[i].make_directory_async(Priority.DEFAULT, cancellable);
			} catch(IOError.EXISTS e) {
				// Created by another process
			}
		}
	}

	namespace FileSettingUtils {
		[CCode (has_target = false)]
		delegate string DefaultPathFunc();

		/// A DefaultPathFunc **MUST** be passed as user_data

		bool @get(Value value, Variant variant, void* user_data)
		requires(variant.is_of_type(VariantType.BYTESTRING))
		requires(user_data != null)
		{
			unowned var uri = variant.get_bytestring();
			File file;
			if (uri == null || uri.length == 0) {
				file = File.new_for_path(((DefaultPathFunc)user_data)());
			} else {
				file = File.new_for_uri(uri);
			}
			value.take_object((owned)file);
			return true;
		}

		Variant @set(Value value, VariantType expected_type, void* user_data)
		requires(expected_type.equal(VariantType.BYTESTRING))
		{
			var? file = value.get_object() as File;

			if (file == null) {
				return null; // Not a bug, a binding deficiency
			}

			return new Variant.bytestring(file.get_uri());
		}
	}
}
