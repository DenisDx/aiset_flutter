part of 'json5.dart';

/// The JSON Pointer token that addresses a new last array
/// item, exactly as the baseline spells it in operation envelopes.
const String appendMarker = '-';

/// Splits a JSON Pointer into unescaped tokens.
///
/// The empty string is the root; every other pointer starts with `/`.
/// `~0` and `~1` are the only escapes. The [appendMarker] token is
/// accepted only when [allowAppend] is set, because plain lookups never
/// address a position past the last item.
///
/// Throws [Json5PathException] (stable code `BAD_REQUEST`) for a pointer
/// that does not start with `/` or that carries a malformed escape.
List<String> parsePointer(String pointer, {bool allowAppend = false}) {
  if (pointer.isEmpty) return const [];
  if (!pointer.startsWith('/')) {
    throw Json5PathException(
        "Path must be empty or start with '/': '$pointer'");
  }
  final raws = pointer.substring(1).split('/');
  return [for (final raw in raws) _unescapeToken(raw, allowAppend)];
}

String _unescapeToken(String raw, bool allowAppend) {
  if (raw == appendMarker && !allowAppend) {
    throw Json5PathException(
        "Array append marker '$appendMarker' is not supported for this operation");
  }
  final out = StringBuffer();
  var index = 0;
  while (index < raw.length) {
    final char = raw[index];
    if (char == '~') {
      final next = index + 1 < raw.length ? raw[index + 1] : '';
      if (next == '0') {
        out.write('~');
      } else if (next == '1') {
        out.write('/');
      } else {
        throw Json5PathException("Malformed escape in path segment: '$raw'");
      }
      index += 2;
      continue;
    }
    out.write(char);
    index++;
  }
  return out.toString();
}

/// Escapes one pointer token for use inside a pointer.
String escapeToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

/// Whether [label] can be written as an unquoted JSON5 key.
///
/// Only ASCII identifier characters qualify, matching the baseline;
/// anything else is emitted as a quoted key.
bool isUnquotedKey(String label) => _identifier.firstMatch(label) != null;

final RegExp _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// Quotes [label] as a JSON5 double-quoted key.
String quoteKey(String label) =>
    '"${label.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

/// The pointer of the container an operation addresses, taken
/// textually so escaped keys survive: `/a~1b/c` has the parent `/a~1b`.
String textualParentPointer(String pointer) {
  final segments = pointer.split('/');
  return segments.take(segments.length - 1).join('/');
}

/// Whether [token] is a plain decimal array index.
///
/// Non-ASCII digit characters are not indices here; the
/// baseline accepts some of them and then crashes on the
/// conversion, so the stricter rule is the compatible one.
bool isIndexToken(String token) =>
    token.isNotEmpty && token.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

/// The numeric value of an index token, or `null` when it exceeds the
/// 64-bit range. An out-of-range index behaves like a missing one in
/// every baseline operation, so `null` maps onto the same outcome.
int? indexValue(String token) => isIndexToken(token) ? int.tryParse(token) : null;
