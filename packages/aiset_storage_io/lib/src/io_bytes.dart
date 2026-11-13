/// Byte-level file helpers of the native-file adapter.
///
/// The adapter stores and reads the ORIGINAL bytes — never a
/// re-encoded guess — so a no-change write is byte-identical,
/// comments, formatting, line endings AND the byte order mark
/// included. Two `dart:io`/`dart:convert` facts drive this file (both
/// verified by executed probes on this SDK):
///
/// * `utf8.decode` STRIPS a leading BOM, and `utf8.encode` re-emits
///   U+FEFF only if it is still in the text. So the mark is preserved
///   by OUR codec, not the runtime's: [_decodeText] detects and
///   re-attaches it, and [_encodeText] turns it back into the
///   three mark bytes — which keeps
///   `encode(decode(bytes)) == bytes` for every readable file.
/// * The revision is the hash of the RAW bytes — mark included —
///   which is exactly the core's `sourceRevisionOfBytes`
///   (equal to the baseline's `revision_of_bytes`, verified by
///   execution).
///
/// The Python baseline decodes with `utf-8-sig` (mark dropped), then
/// re-attaches it only when its BOM flag says so — and the service
/// computes that flag from the ALREADY-decoded text, so the flag is
/// always false and the mark is silently lost on the first save
/// (verified by execution). We do not reproduce that defect
/// (PENDING-A42a, `SPEC_.md` amendment 38).
part of 'native_file_storage.dart';

/// The "file not found" OS error code. It is 2 (ENOENT) on Linux,
/// macOS and Windows, and it is the only [FileSystemException] code
/// the adapter maps to "absent"; every other read failure stays a
/// storage error, so an unavailable document is never mistaken for no
/// document (`SPEC.md` amendment 11, STO-05).
const int _enoent = 2;

/// The "file exists" OS error code (EEXIST on POSIX): the
/// exclusive-create collision the conflicted copy retries past
/// instead of overwriting a preserved copy or crashing.
const int _eexist = 17;

/// The write-side OS errors that prove NOTHING LANDED at the target:
/// permission, capacity, and a directory standing in the target's
/// place. Such an attempt answers [AisetCommitStatus.rejected] — "the
/// adapter refused the write on policy or capacity grounds. Nothing
/// was written." — instead of burning the retry budget or claiming an
/// uncertainty the adapter does not actually have. A quota or capacity
/// refusal MUST NOT damage the previous version (`SPEC.md` amendment
/// 11): the target is touched only by the rename that just failed.
///
/// DECISION(cross-platform): the set lists the POSIX errnos; on
/// Windows `dart:io` reports its own error numbers, and anything
/// unrecognized lands in the conservative
/// [AisetCommitStatus.uncertain] class. That is the safe direction of
/// the mistake: uncertain costs the caller a re-read, while `rejected`
/// is claimed only where the platform proves the target was untouched.
/// Verified on this container's Linux; the Windows classification is
/// untested here (D-06 honesty).
const Set<int> _refusedWriteErrors = {
  1, // EPERM
  13, // EACCES
  20, // ENOTDIR
  21, // EISDIR — the document path occupied by a directory
  28, // ENOSPC
  40, // ELOOP
  122, // EDQUOT
};

/// Encodes document [text] to stored bytes; a leading U+FEFF
/// character becomes the UTF-8 BOM sequence.
Uint8List _encodeText(String text) => Uint8List.fromList(utf8.encode(text));

/// Decodes stored [bytes] to document text, keeping a leading BOM as
/// the U+FEFF character so the text re-encodes to the same bytes.
/// A malformed sequence is a [FormatException] that the caller turns
/// into the adapter's corrupt-document failure.
String _decodeText(Uint8List bytes) {
  final hasBom = _startsWithBom(bytes);
  final body = hasBom ? Uint8List.sublistView(bytes, 3) : bytes;
  final text = utf8.decode(body);
  return hasBom ? '\uFEFF$text' : text;
}

/// Whether [bytes] opens with the UTF-8 byte order mark.
bool _startsWithBom(List<int> bytes) =>
    bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;

/// Pushes the written bytes out of the user-space buffer.
///
/// DECISION(durability): `dart:io` exposes no `fsync` and no directory
/// sync, so a power loss can lose a rename the baseline would
/// (best-effort) have survived — the baseline fsyncs the temp file and
/// the parent directory, and silently ignores a refused directory
/// fsync. Atomicity against concurrent readers and writers — the
/// property the CAS promise and the two-process race test are about —
/// comes from the same-directory rename, which `dart:io` does provide,
/// and not from fsync. Closing the power-loss durability gap needs FFI
/// and is a 2E-c decision, not a silent extra dependency here.
Future<void> _flushToOs(RandomAccessFile file) => file.flush();

/// The last path component, for either separator.
String _basename(String path) {
  final unix = path.lastIndexOf('/');
  final win = path.lastIndexOf(r'\');
  final cut = unix > win ? unix : win;
  return cut < 0 ? path : path.substring(cut + 1);
}
