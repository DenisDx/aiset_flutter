part of 'json5.dart';

/// A contiguous region of source text in both offset spaces.
///
/// Unit offsets are UTF-16 code-unit offsets (plain Dart `String` indices);
/// byte offsets are UTF-8 byte offsets into the encoded document. They differ
/// exactly where the text before the region contains non-ASCII
/// code points, e.g. astral-plane characters cost 2 code units but 4 bytes.
final class SourceSpan {
  /// Creates a span from already-resolved offsets.
  const SourceSpan(this.startUnit, this.endUnit, this.startByte, this.endByte);

  /// UTF-16 code-unit offset of the first code unit of the region.
  final int startUnit;

  /// UTF-16 code-unit offset just past the last code unit of the region.
  final int endUnit;

  /// UTF-8 byte offset of the first byte of the region.
  final int startByte;

  /// UTF-8 byte offset just past the last byte of the region.
  final int endByte;

  /// Length of the region in UTF-16 code units.
  int get lengthUnits => endUnit - startUnit;

  /// Length of the region in UTF-8 bytes.
  int get lengthBytes => endByte - startByte;

  /// Whether the region is empty.
  bool get isEmpty => startUnit == endUnit;

  @override
  bool operator ==(Object other) =>
      other is SourceSpan &&
      other.startUnit == startUnit &&
      other.endUnit == endUnit &&
      other.startByte == startByte &&
      other.endByte == endByte;

  @override
  int get hashCode => Object.hash(startUnit, endUnit, startByte, endByte);

  @override
  String toString() =>
      'SourceSpan(units $startUnit..$endUnit, bytes $startByte..$endByte)';
}

/// Maps UTF-16 code-unit offsets to UTF-8 byte offsets for one source string.
///
/// Unpaired surrogates are counted as 3 bytes (CESU-8/WTF-8 width). Such
/// text cannot be UTF-8 encoded by `dart:convert` anyway; the table stays
/// total so span math never throws.
final class OffsetMap {
  /// Builds the mapping table for [text] in one pass.
  OffsetMap.fromText(String text) : _byteOf = Uint32List(text.length + 1) {
    var bytes = 0;
    var i = 0;
    while (i < text.length) {
      _byteOf[i] = bytes;
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          _byteOf[i + 1] = bytes + 1; // surrogate half, not a boundary
          bytes += 4;
          i += 2;
          continue;
        }
      }
      bytes += _utf8Width(unit);
      i += 1;
    }
    _byteOf[text.length] = bytes;
    byteLength = bytes;
  }

  final Uint32List _byteOf;

  /// Total UTF-8 length of the source text in bytes.
  late final int byteLength;

  /// The UTF-8 byte offset corresponding to code-unit offset [unitOffset].
  int byteOf(int unitOffset) => _byteOf[unitOffset];

  static int _utf8Width(int unit) {
    if (unit < 0x80) return 1;
    if (unit < 0x800) return 2;
    return 3; // BMP character, or a lone surrogate counted WTF-8 style
  }
}
