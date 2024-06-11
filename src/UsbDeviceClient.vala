/* UsbDeviceClent.vala
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
	enum UsbDeviceClientStatus {
		UNINITIALIZED,
		CONNECTED,
		TRANSFER,
		FATAL_ERROR
	}

	errordomain UsbDeviceClientError {
		FAILED
	}

	private enum UsbCommands {
		START_SESSION,
		SEND_FILE_PROPERTIES,
		CANCEL_FILE_TRANSFER,
		SEND_NSP_HEADER,
		END_SESSION,
		START_EXTRACTED_FS_DUMP,
		END_EXTRACTED_FS_DUMP,
	}

	// Error codes directly map to responses
	private errordomain UsbDeviceProtocolError {
		INVALID_MAGIC_WORD = 4,
		UNSUPPORTED_COMMAND = 5,
		UNSUPPORTED_ABI_VERSION = 6,
		MALFORMED_COMMAND = 7,
		IO_ERROR = 8
	}

	private struct NspDumpStatus {
		int64 total_size; ///< With header
		int64 transferred_size; ///< Without header
		int64 header_size;
		File file;
		FileOutputStream ostream;
		FileTransferInhibitor inhibitor;
		GenericArray<string>? nca_checksums; // Prefixes for NCA files
	}

	/**
	 * This is intended for breaking changes or new fields in existing commands.
	 * New commands/possible invocations of commands are added without version checks.
	 */
	[Flags]
	private enum ClientFeatures {
		NONE = 0,
	}

	private const string COMMAND_MAGIC = "NXDT";
	private const uint32 HEADER_SIZE = 0x10;
	private const uint32 RESPONSE_SIZE = 0x10;
	private const uint DEFAULT_TIMEOUT = 5000;
	private const uint32 STATUS_SUCCESS = 0x0;
	internal const uint32 BLOCK_SIZE = 0x800000;

	private const string NSP_MAGIC = "PFS0";

	// Throw errors that are not fatal to device as UsbDeviceProtocolError
	private Error error_to_recoverable(Error err) {
		try {
			throw err;
		} catch(UsbDeviceProtocolError e) {
			// Preserve error code
			return e;
		} catch(GUsb.DeviceError e) {
			// UBS stack errors are not recoverable
			return e;
		} catch(IOError.CANCELLED e) {
			// Cancellation must not be silenced
			return e;
		} catch(Error e) {
			return new UsbDeviceProtocolError.IO_ERROR(e.message);
		}
	}

	// TODO: utilize new ABI commands instead of guessing from prefixes
	private bool is_mass_transfer_path(string path) {
		const string[] PATHS = {
			"/NCA FS/User/Extracted",
			"/NCA FS/System/Extracted",
			"/atmosphere/contents",
		};

		foreach(unowned var prefix in PATHS) {
			if (path.has_prefix(prefix)) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Convert path from device to one that can be used as relative to output directory.
	 */
	private string device_to_relative_path(owned string path) throws ConvertError
	ensures(!Path.is_absolute(result))
	{
		if (new Application().flatten_output) {
			/*
			 * Completely flattening these dumps is a bad idea.
			 * However, it's possible to strip long prefixes and thus avoid extra nesting.
			 */
			const string[] STRIP_AND_PRESERVE = {
				"/NCA FS/User/Extracted",
				"/NCA FS/System/Extracted",
				"/NCA FS/User/Raw",
				"/NCA FS/System/Raw",
				"/NCA/User",
				"/NCA/System",
				"/HFS/Extracted",
				"/HFS/Raw",
				"/atmosphere/contents",
			};

			bool preserve_path = false;

			foreach(unowned var prefix in STRIP_AND_PRESERVE) {
				if (path.has_prefix(prefix)) {
					path = path[prefix.length:];
					preserve_path = true;
					break;
				}
			}

			if (!preserve_path) {
				path = Path.get_basename(path);
			}
		}

		return Path.skip_root(path) ?? path;
	}

	private async File get_dump_target(string filepath_utf8, int64 file_size, Cancellable? cancellable = null) throws Error {
		var main_dir = new Application().destination_directory;
		var filepath = device_to_relative_path(Filename.from_utf8(filepath_utf8, -1, null, null));

		var dest_file = main_dir.resolve_relative_path(filepath);
		var dest_dir = dest_file.get_parent();
		yield create_directory_with_parents_async(dest_dir, cancellable);

		var info = yield dest_dir.query_filesystem_info_async(FileAttribute.FILESYSTEM_FREE, Priority.DEFAULT, cancellable);

		if (info.has_attribute(FileAttribute.FILESYSTEM_FREE)) {
			var free_space = info.get_attribute_uint64(FileAttribute.FILESYSTEM_FREE);
			debug("Required space: %s, free space: %s", format_size(file_size), format_size(free_space));
			if (free_space < file_size) {
				throw new IOError.NO_SPACE(_("Not enough space for dump (%s required)"), format_size(file_size));
			}
		} else {
			debug("Can't query free space");
		}

		return dest_file;
	}

	/**
	 * The class that handles actual communication with device.
	 */
	class UsbDeviceClient: Object {
		public UsbDeviceOpener devopener { private get; construct; }
		public GUsb.Device dev { get { return devopener.dev; } }
		public Cancellable? cancellable { get; construct; }
		public UsbDeviceClientStatus status { get; private set; default = UNINITIALIZED; }
		public string? version_string { get; private set; default = null; }

		// User-visible, so in NSP mode they reflect status of the whole NSP
		public string transfer_file_name { get; private set; default = ""; }
		public string transfer_file_name_inner { get; private set; default = ""; } // Used in NSP mode
		public int64 transfer_total_bytes { get; private set; default = 0; }
		public int64 transfer_current_bytes { get; private set; default = 0; }
		public int64 transfer_started_time { get; private set; default = 0; }

		public uint16 max_packet_size { get {
			if (endpoint_input != null) {
				return endpoint_input.get_maximum_packet_size();
			} else {
				return 0;
			}
		} }

		public signal void transfer_started(File file, bool mass_transfer);
		public signal void transfer_got_empty_file(File file, bool mass_transfer);
		public signal void transfer_next_inner_file(); // Used in NSP mode
		public signal void transfer_progress();
		public virtual signal void transfer_complete(File file, bool mass_transfer) {
			nsp_dump_status = null;
			status = CONNECTED;
		}
		// MAY be issued without prior `transfer_started` if creating empty file failed
		public virtual signal void transfer_failed(File file, bool cancelled) {
			nsp_dump_status = null;
			status = CONNECTED;
		}

		private static GenericSet<uint8> supported_abis = new GenericSet<uint8>(null, null);

		private static uint8 make_abi_version(uint8 major, uint8 minor)
		requires (major < 16 && minor < 16) {
			return major << 4 | minor;
		}

		static construct {
			supported_abis.add(make_abi_version(1, 1));
			supported_abis.add(make_abi_version(1, 2));
		}

		private GUsb.Interface iface = null;
		private GUsb.Endpoint endpoint_input = null;
		private GUsb.Endpoint endpoint_output = null;
		private NspDumpStatus? nsp_dump_status = null;
		private ClientFeatures features = NONE;

		public UsbDeviceClient(owned UsbDeviceOpener devopener_, Cancellable? cancellable_ = null) throws Error {
			Object(devopener: (owned)devopener_, cancellable: cancellable_);
			setup();
		}

		public void setup() throws Error
		requires (status == UNINITIALIZED || status == FATAL_ERROR)
		{
			dev.reset(); // Seems to be a recommended thing to do; does not incur delays
			status = UNINITIALIZED;
			nsp_dump_status = null;
			version_string = null;

			iface = dev.get_interface(0xFF, 0xFF, 0xFF);
			if (iface == null) {
				throw new UsbDeviceClientError.FAILED("Unable to find expected device interface");
			}
			dev.claim_interface(iface.get_index(), BIND_KERNEL_DRIVER);

			foreach(unowned var endpoint in iface.get_endpoints()) {
				if (endpoint.get_direction() == DEVICE_TO_HOST) {
					endpoint_input = endpoint;
				} else {
					endpoint_output = endpoint;
				}
			}

			if (endpoint_input == null || endpoint_output == null) {
				throw new UsbDeviceClientError.FAILED("Unable to find endpoints");
			}

			usb_handler.begin();
		}

		private async void usb_handler() {
			try {
				while (true) {
					try {
						uint8 header_buf[HEADER_SIZE];
						debug("Waiting for command header");
						var bytes_read = yield dev.bulk_transfer_async(endpoint_input.get_address(), header_buf, 0, cancellable);
						debug("Got command header");
						if (bytes_read != HEADER_SIZE) {
							throw new UsbDeviceClientError.FAILED("Failed to read command header");
						}

						var header_istream = make_input_stream(header_buf);
						if (header_istream.read_bytes(COMMAND_MAGIC.length, cancellable).compare(new Bytes.static(COMMAND_MAGIC.data)) != 0) {
							throw new UsbDeviceProtocolError.INVALID_MAGIC_WORD("Invalid header magic");
						}

						var command_id = header_istream.read_uint32(cancellable);
						var command_block_size = header_istream.read_uint32(cancellable);
						var command_block_buf = new uint8[command_block_size];

						if (command_block_size > 0) {
							bytes_read = yield dev.bulk_transfer_async(
								endpoint_input.get_address(),
								command_block_buf[:adjust_length_for_zlt(command_block_size)],
								DEFAULT_TIMEOUT,
								cancellable
							);

							if (bytes_read != command_block_size) {
								throw new UsbDeviceClientError.FAILED("Failed to read command block");
							}
						}

						switch(command_id) {
							case UsbCommands.START_SESSION:
								yield start_session(command_block_buf);
								break;
							case UsbCommands.END_SESSION:
								yield end_session(command_block_buf);
								break;

							case UsbCommands.SEND_FILE_PROPERTIES:
								yield file_transfer(command_block_buf);
								break;
							case UsbCommands.CANCEL_FILE_TRANSFER:
								yield standalone_cancel(command_block_buf);
								break;
							case UsbCommands.SEND_NSP_HEADER:
								yield nsp_header(command_block_buf);
								break;

							case UsbCommands.START_EXTRACTED_FS_DUMP:
								yield start_extracted_fs_dump(command_block_buf);
								break;
							case UsbCommands.END_EXTRACTED_FS_DUMP:
								yield end_extracted_fs_dump(command_block_buf);
								break;
							default:
								throw new UsbDeviceProtocolError.UNSUPPORTED_COMMAND("Unsupported command 0x%X", command_id);
						}
					} catch(UsbDeviceProtocolError e) {
						// Explicitly designed to translate to status codes 1:1
						report_error("Error during device communication", e.message);
						yield send_status_response(e.code);
					}
				}
			} catch(GUsb.DeviceError.CANCELLED e) {
			} catch(IOError.CANCELLED e) {
			} catch(GUsb.DeviceError.NO_DEVICE e) {
				// Expected on device disconnect
			} catch(Error e) {
				if (nsp_dump_status != null) {
					transfer_failed.emit(nsp_dump_status.file, false);
				}

				report_error("Error during device communication", e.message);
				status = FATAL_ERROR;
				return;
			} finally {
				version_string = null;
			}
			status = UNINITIALIZED;
			debug("Normal exit from device loop");
		}

		private async void start_session(uint8[] command) throws Error {
			debug("Starting session");
			if (command.length != 0x10) {
				throw new UsbDeviceProtocolError.MALFORMED_COMMAND("StartSession command with invalid length 0x%X", command.length);
			}
			var istream = make_input_stream(command);

			// NXDT version
			var ver_major = istream.read_byte(cancellable);
			var ver_minor = istream.read_byte(cancellable);
			var ver_micro = istream.read_byte(cancellable);

			var abi_ver = istream.read_byte(cancellable);
			if (!(abi_ver in supported_abis)) {
				throw new UsbDeviceProtocolError.UNSUPPORTED_ABI_VERSION("Unsupported USB ABI version %s", format_usb_abi(abi_ver));
			}

			{
				features = NONE;

				// Put feature selection code here
			}

			var git_hash = (string)istream.read_bytes(8, cancellable).get_data();
			version_string = @"v$(ver_major).$(ver_minor).$(ver_micro) ($(git_hash))";
			yield send_status_success();

			status = CONNECTED;
			nsp_dump_status = null;
			debug("Device initialized");
		}

		private async void end_session(uint8[] command) throws Error {
			try {
				if (command.length != 0x0) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("EndSession command with invalid length 0x%X", command.length);
				}

				if (nsp_dump_status != null) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("EndSession in the middle of an NSP transfer");
				}
			} finally {
				debug("Device deinitialized");
				status = UNINITIALIZED;
				nsp_dump_status = null;
			}

			yield send_status_success();
		}

		private async void file_transfer(uint8[] command) throws Error {
			if (command.length != 0x320) {
				throw new UsbDeviceProtocolError.MALFORMED_COMMAND("SendFileProperties command with invalid length 0x%X", command.length);
			}
			var checksum_mode = new Application().nca_checksum_mode;
			var istream = make_input_stream(command);

			var file_size = istream.read_int64(cancellable);
			/*var filename_len = */istream.read_uint32(cancellable);
			var nsp_header_size = istream.read_uint32(cancellable);

			if (status != CONNECTED && (status != TRANSFER || nsp_dump_status == null)) {
				throw new UsbDeviceProtocolError.MALFORMED_COMMAND("SendFileProperties requires prior connection");
			}

			var filename = (string)istream.read_bytes(0x301, cancellable).get_data();
			File file;
			FileOutputStream ostream;
			FileTransferInhibitor inhibitor;

			try {
				if (nsp_dump_status == null) {
					file = yield get_dump_target(filename, file_size, cancellable);
					ostream = yield file.replace_async(null, false, REPLACE_DESTINATION, Priority.DEFAULT, cancellable);
					inhibitor = new FileTransferInhibitor();
				} else {
					file = nsp_dump_status.file;
					ostream = nsp_dump_status.ostream;
					inhibitor = nsp_dump_status.inhibitor;
				}
			} catch(Error e) {
				throw error_to_recoverable(e);
			}

			if (nsp_header_size > 0) {
				if (nsp_dump_status != null) {
					transfer_failed.emit(nsp_dump_status.file, false);
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("Unexpected NSP start command");
				}

				if (file_size < nsp_header_size) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("NSP file size smaller than header");
				}

				ostream.seek(nsp_header_size, SET, cancellable);

				freeze_notify();
				try {
					transfer_file_name = filename;
					transfer_file_name_inner = "";
					transfer_total_bytes = file_size;
					transfer_current_bytes = 0;
					transfer_started_time = 0;
					status = TRANSFER;
				} finally {
					thaw_notify();
				}

				nsp_dump_status = NspDumpStatus() {
					total_size = file_size,
					transferred_size = 0,
					header_size = nsp_header_size,
					file = file,
					ostream = ostream,
					inhibitor = inhibitor,
					nca_checksums = checksum_mode == COMPATIBLE ? new GenericArray<string>() : null,
				};

				yield send_status_success();
				transfer_started.emit(file, false);
				debug("Entered NSP mode");
				return;
			}

			if (file_size == 0) {
				try {
					if (nsp_dump_status == null) {
						yield ostream.close_async(Priority.DEFAULT, cancellable);
						transfer_got_empty_file.emit(file, is_mass_transfer_path(filename));
					}
					yield send_status_success();
					return;
				} catch(Error e) {
					transfer_failed.emit(file, false);
					throw error_to_recoverable(e);
				}
			}

			// Enter file transfer mode
			yield send_status_success();
			status = TRANSFER;
			if (nsp_dump_status == null) {
				freeze_notify();
				try {
					transfer_file_name = filename;
					transfer_file_name_inner = "";
					transfer_total_bytes = file_size;
					transfer_current_bytes = 0;
					transfer_started_time = 0;
				} finally {
					thaw_notify();
				}

				transfer_started.emit(file, is_mass_transfer_path(filename));
			} else {
				transfer_file_name_inner = filename;
				transfer_next_inner_file.emit();
			}

			Checksum? checksum = null;
			if (filename.has_suffix(".nca")) {
				if (checksum_mode != NONE || nsp_dump_status?.nca_checksums != null) {
					checksum = new Checksum(SHA256);
				}
			}

			debug("Transfer of file %s started", filename);

			/*
			 * We're in file transfer mode now. As implemented currently, it means we must not report errors to console,
			 * but instead throw a critical error and let it time out. Might change in future ABI revision.
			 */

			try {
				var read_buffer = new uint8[BLOCK_SIZE];
				var read_size = BLOCK_SIZE;
				int64 bytes_transferred = 0;

				while(bytes_transferred < file_size) {
					var bytes_remaining = file_size - bytes_transferred;
					if (bytes_remaining <= BLOCK_SIZE) {
						read_size = adjust_length_for_zlt(read_size);
					}

					var bytes_read = yield dev.bulk_transfer_async(
						endpoint_input.get_address(),
						read_buffer[:read_size],
						DEFAULT_TIMEOUT,
						cancellable
					);

					unowned var incoming_data = read_buffer[:bytes_read];

					if (bytes_read == HEADER_SIZE) {
						// Check if it's a transfer canceling message
						var header_istream = make_input_stream(incoming_data);
						if (header_istream.read_bytes(COMMAND_MAGIC.length, cancellable).compare(new Bytes.static(COMMAND_MAGIC.data)) == 0 &&
							header_istream.read_uint32(cancellable) == UsbCommands.CANCEL_FILE_TRANSFER
						) {
							// Transfer canceled
							debug("Transfer canceled");
							yield ostream.close_async(Priority.DEFAULT, cancellable);
							transfer_failed.emit(file, true);
							yield send_status_success();
							return;
						}
					}

					yield ostream.write_all_async(incoming_data, Priority.DEFAULT, cancellable, null);
					bytes_transferred += bytes_read;
					transfer_current_bytes += bytes_read;
					if (nsp_dump_status != null) {
						nsp_dump_status.transferred_size += bytes_read;
					}

					if (checksum != null) {
						checksum.update(incoming_data, incoming_data.length);
					}

					if (transfer_started_time == 0) {
						transfer_started_time = get_monotonic_time();
					}

					transfer_progress.emit();
				}

				debug("File transfer finished");
			} catch(Error e) {
				transfer_failed.emit(file, false);
				throw e;
			}

			try {
				if (nsp_dump_status == null) {
					transfer_current_bytes = transfer_total_bytes;
					transfer_progress.emit();
					yield ostream.close_async(Priority.DEFAULT, cancellable);
					// In NSP mode it is emitted from nsp_header
					transfer_complete.emit(file, is_mass_transfer_path(filename));
				} else {
					transfer_file_name_inner = "";
					transfer_next_inner_file.emit();
				}

				if (checksum != null) {
					var checksum_string_abridged = checksum.get_string()[:32];
					// Strict mode or standalone (thus unmodified) NCA
					if (checksum_mode == STRICT || (checksum_mode == COMPATIBLE && nsp_dump_status == null)) {
						var basename = Path.get_basename(filename);
						if (!basename.has_prefix(checksum_string_abridged)) {
							if (!ostream.is_closed()) {
								// Avoid synchronous closing in destructor
								yield ostream.close_async(Priority.DEFAULT, cancellable);
							}

							throw new UsbDeviceProtocolError.IO_ERROR(_("NCA checksum verification failed (non-standard dump options?)"));
						} else {
							debug("Checksum verification passed");
						}
					}
					// Always check for this so that messing with settings during the transfer will not make it fail
					if (nsp_dump_status?.nca_checksums != null) {
						nsp_dump_status.nca_checksums.add((owned)checksum_string_abridged);
						debug("Checksum pushed into queue");
					}
				}

				yield send_status_success();
			} catch(Error e) {
				// Status is expected at the end of transmission, so we can make errors recoverable at this point
				transfer_failed.emit(file, false);
				throw error_to_recoverable(e);
			}
		}

		private async void standalone_cancel(uint8[] header) throws Error {
			if (nsp_dump_status == null) {
				throw new UsbDeviceProtocolError.MALFORMED_COMMAND("Cancellation command without an ongoing transfer");
			}

			try {
				yield nsp_dump_status.ostream.close_async(Priority.DEFAULT, cancellable);
				yield send_status_success();
			} catch(Error e) {
				throw error_to_recoverable(e);
			} finally {
				transfer_failed.emit(nsp_dump_status.file, true);
			}
		}

		private async void nsp_header(uint8[] header) throws Error {
			try {
				if (nsp_dump_status == null) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("NSP header outside of NSP transfer");
				}

				if (nsp_dump_status.header_size != header.length) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("NSP header size mismatch");
				}

				if ((nsp_dump_status.transferred_size + nsp_dump_status.header_size) != nsp_dump_status.total_size) {
					throw new UsbDeviceProtocolError.MALFORMED_COMMAND("NSP header before transfer completion");
				}

				transfer_file_name_inner = _("NSP header");
				transfer_next_inner_file.emit();

				if (nsp_dump_status.nca_checksums != null) {
					verify_nsp_checksums(header, nsp_dump_status.nca_checksums);
				}

				var ostream = nsp_dump_status.ostream;
				ostream.seek(0, SET, cancellable);
				debug("Writing header");
				yield ostream.write_all_async(header, Priority.DEFAULT, cancellable, null);
				transfer_current_bytes = transfer_total_bytes;
				transfer_progress.emit();
				debug("Closing file");
				yield ostream.close_async(Priority.DEFAULT, cancellable);
				debug("File closed");

				yield send_status_success();
				transfer_complete.emit(nsp_dump_status.file, false);
			} catch(Error e) {
				transfer_failed.emit(nsp_dump_status.file, false);
				throw error_to_recoverable(e);
			}
		}

		private async void start_extracted_fs_dump(uint8[] header) throws Error {
			debug("start_extracted_fs_dump called");
			yield send_status_success();
		}

		private async void end_extracted_fs_dump(uint8[] header) throws Error {
			debug("end_extracted_fs_dump called");
			yield send_status_success();
		}

		private void verify_nsp_checksums(uint8[] header, GenericArray<string> checksums) throws Error {
			var istream = make_input_stream(header);
			if (istream.read_bytes(NSP_MAGIC.length, cancellable).compare(new Bytes.static(NSP_MAGIC.data)) != 0) {
				throw new UsbDeviceProtocolError.IO_ERROR("NSP header has invalid magic");
			}

			var entry_count = istream.read_uint32(cancellable);
			if (checksums.length > entry_count) {
				throw new UsbDeviceProtocolError.IO_ERROR("NSP header has less entries than there are checksummed files");
			}

			/*var string_table_size =*/ istream.read_uint32(cancellable);
			istream.seek(0x4, CUR, cancellable); // Reserved
			istream.seek(0x18 * entry_count, CUR, cancellable); // PartitionEntry table
			int checksums_idx = 0;

			for (int i = 0; i < entry_count; ++i) {
				var fname = istream.read_upto("\0", 1, null, cancellable);
				if ((i + 1) != entry_count) {
					istream.read_byte(cancellable);
				}

				if (fname.has_suffix(".nca")) {
					var checksum = checksums[checksums_idx++];
					if (!fname.has_prefix(checksum)) {
						throw new UsbDeviceProtocolError.IO_ERROR(_("NCA checksum verification failed"));
					}

					debug("Delayed checksum verification for file %s passed", fname);
				}
			}

			if (checksums_idx != checksums.length) {
				throw new UsbDeviceProtocolError.IO_ERROR("NCA checksum count mismatch");
			}
		}

		private DataInputStream make_input_stream(uint8[] data) {
			// Note: sadly, this creates a copy of data
			return new DataInputStream(new MemoryInputStream.from_data(data)) {
				byte_order = LITTLE_ENDIAN
			};
		}

		private DataOutputStream make_output_stream(uint8[] data) {
			return new DataOutputStream(MemoryOutputStream.with_data(data)) {
				byte_order = LITTLE_ENDIAN
			};
		}

		private async void send_status_success() throws Error {
			yield send_status_response(STATUS_SUCCESS);
		}

		private uint32 adjust_length_for_zlt(uint32 orig_length) {
			if (orig_length != 0 && (orig_length & (endpoint_input.get_maximum_packet_size() - 1)) == 0) {
				return orig_length + 1;
			} else {
				return orig_length;
			}
		}

		private async void send_status_response(uint32 code) throws Error {
			uint8 response[RESPONSE_SIZE];
			var ostream = make_output_stream(response);
			ostream.put_string(COMMAND_MAGIC, cancellable);
			ostream.put_uint32(code, cancellable);
			ostream.put_uint16(endpoint_input.get_maximum_packet_size(), cancellable);
			ostream.flush(cancellable);
			var bytes_sent = yield dev.bulk_transfer_async(endpoint_output.get_address(), response, DEFAULT_TIMEOUT, cancellable);
			if (bytes_sent != RESPONSE_SIZE) {
				throw new UsbDeviceClientError.FAILED("Failed to send status");
			}
		}
	}
}
