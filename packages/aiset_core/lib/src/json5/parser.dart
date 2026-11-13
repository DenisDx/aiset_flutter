part of 'json5.dart';

/// Recursive-descent parser producing the lossless CST.
///
/// The grammar and the accept/reject semantics follow the baseline
/// engine (SPEC.md amendments 3 and 32); the scanning, trivia
/// partitioning and tree shape are Dart-native. Notable grammar
/// points, all matching the baseline:
///
/// * A `:` must follow the key token with no gap; a `,` must follow the
///   value token with no gap. Whitespace or a comment in either place
///   makes the document invalid, never silently normalized.
/// * A literal token absorbs `/`, so `1/*c*/` is one
///   invalid value token, while `"x"/*c*/` ends the value and starts a
///   trailing comment.
/// * Whitespace is exactly the baseline set: space, tab, CR, LF, FF,
///   VT, NBSP and BOM. `\u2028`/`\u2029` only act inside
///   strings and line comments.
/// * Where the baseline crashes on truncated input (an
///   `IndexError` when a key is expected at end of text) this parser
///   rejects with a positioned [Json5ParseException];
///   exception types are tier-3 and the accept/reject outcome is
///   unchanged.
class _Parser {
  /// Creates a parser for [text]; [origin] labels errors.
  _Parser(this.text, this.origin) : offsets = OffsetMap.fromText(text);

  final String text;
  final String origin;
  final OffsetMap offsets;
  int _pos = 0;

  static final RegExp _number = RegExp(
      r'^[+-]?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|Infinity|NaN)$');
  static final RegExp _templateInner =
      RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)(?::-([\s\S]*))?$');
  static final RegExp _placeholder =
      RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([\s\S]*?))?\}');
  static final RegExp _hex4 = RegExp(r'^[0-9a-fA-F]{4}$');
  static final RegExp _hex2 = RegExp(r'^[0-9a-fA-F]{2}$');
  static final RegExp _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Parses the whole document: trivia, one root value, trivia.
  Json5Document run() {
    final leading = _readTrivia();
    final root = _parseValue();
    final trailing = _readTrivia();
    if (_pos < text.length) _fail('Trailing content after the root value');
    final document = Json5Document._(
      text: text,
      origin: origin,
      offsets: offsets,
      leading: leading,
      root: root,
      trailing: trailing,
    );
    for (final node in leading) {
      if (node is CommentNode) node._attach(CommentRole.documentLeading, document);
    }
    for (final node in trailing) {
      if (node is CommentNode) node._attach(CommentRole.documentTrailing, document);
    }
    // Opening comments survive on the root container. The baseline
    // overwrites the root's own opening-comment attribute with the
    // document comments (an internal attribute quirk
    // that does not affect round-trip or entry ownership); the
    // Dart tree keeps them classified as `opening` on the root.
    final List<CstNode> rootOpening = switch (root) {
      final ObjectNode o => o.afterOpen,
      final ArrayNode a => a.afterOpen,
      final ValueNode _ => const <CstNode>[],
    };
    for (final node in rootOpening) {
      if (node is CommentNode) node._attach(CommentRole.opening, root);
    }
    return document;
  }

  // -- low level -------------------------------------------------------

  Never _fail(String message, [int? at]) {
    throw Json5ParseException(
      message: message,
      text: text,
      offsets: offsets,
      offsetUnit: at ?? _pos,
      origin: origin,
    );
  }

  SourceSpan _spanTo(int startUnit, [int? endUnit]) {
    final end = endUnit ?? _pos;
    return SourceSpan(
        startUnit, end, offsets.byteOf(startUnit), offsets.byteOf(end));
  }

  bool _startsWith(String pattern, [int? at]) =>
      text.startsWith(pattern, at ?? _pos);

  String? get _peek => _pos < text.length ? text[_pos] : null;

  static bool _isWhitespace(int c) =>
      c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x0C ||
      c == 0x0B ||
      c == 0xA0 ||
      c == 0xFEFF;

  static bool _isLineBreak(int c) =>
      c == 0x0D || c == 0x0A || c == 0x2028 || c == 0x2029;


  /// Consumes whitespace plus any number of comments (baseline
  /// `skip_trivia`), keeping every run as a node.
  List<CstNode> _readTrivia() {
    final out = <CstNode>[];
    while (true) {
      final ws = _whitespaceRun();
      if (ws != null) out.add(ws);
      if (_startsWith('//')) {
        out.add(_lineComment());
        continue;
      }
      if (_startsWith('/*')) {
        out.add(_blockComment());
        continue;
      }
      return out;
    }
  }

  /// Consumes comments that follow without crossing a newline; only
  /// spaces and tabs may precede each of them (baseline
  /// `take_same_line_comments`). The whitespace before a grabbed comment
  /// becomes a node; whitespace with no following comment is left alone.
  List<CstNode> _readSameLineTrivia() {
    final out = <CstNode>[];
    while (true) {
      var probe = _pos;
      while (probe < text.length &&
          (text.codeUnitAt(probe) == 0x20 || text.codeUnitAt(probe) == 0x09)) {
        probe++;
      }
      if (probe >= text.length || text.codeUnitAt(probe) == 0x0A) return out;
      if (_startsWith('//', probe) || _startsWith('/*', probe)) {
        if (probe > _pos) {
          out.add(WhitespaceNode(text.substring(_pos, probe), span: _spanTo(_pos, probe)));
        }
        _pos = probe;
        out.add(text.codeUnitAt(probe) == 0x2F && text.codeUnitAt(probe + 1) == 0x2F
            ? _lineComment()
            : _blockComment());
        continue;
      }
      return out;
    }
  }

  WhitespaceNode? _whitespaceRun() {
    final start = _pos;
    while (_pos < text.length && _isWhitespace(text.codeUnitAt(_pos))) {
      _pos++;
    }
    if (_pos == start) return null;
    return WhitespaceNode(text.substring(start, _pos), span: _spanTo(start));
  }

  CommentNode _lineComment() {
    final start = _pos;
    _pos += 2;
    while (_pos < text.length && !_isLineBreak(text.codeUnitAt(_pos))) {
      _pos++;
    }
    return CommentNode(CommentKind.line, text.substring(start, _pos), span: _spanTo(start));
  }

  CommentNode _blockComment() {
    final start = _pos;
    final end = text.indexOf('*/', _pos + 2);
    if (end < 0) _fail('Unterminated block comment', start);
    _pos = end + 2;
    return CommentNode(CommentKind.block, text.substring(start, _pos), span: _spanTo(start));
  }

  // -- values ----------------------------------------------------------

  ValueNode _parseValue() {
    if (_pos >= text.length) _fail('Unexpected end of input');
    final c = text[_pos];
    if (c == '{') return _parseObject();
    if (c == '[') return _parseArray();
    if (c == '"' || c == "'") return _parseString();
    if (_startsWith('\${')) return _parseTemplate();
    return _parseLiteral();
  }

  ObjectNode _parseObject() {
    final start = _pos;
    _pos++;
    final open = TokenNode('{', span: _spanTo(start, start + 1));
    final afterOpen = _readSameLineTrivia();
    final members = <MemberNode>[];
    final seen = <String>{};
    while (true) {
      final pending = _readTrivia();
      if (_peek == '}') {
        final closeStart = _pos;
        _pos++;
        final close = TokenNode('}', span: _spanTo(closeStart));
        final node = ObjectNode(
          open: open,
          afterOpen: afterOpen,
          members: members,
          beforeClose: pending,
          close: close,
          span: _spanTo(start),
        );
        for (final t in pending) {
          if (t is CommentNode) t._attach(CommentRole.blockEnd, node);
        }
        return node;
      }
      final key = _parseKey();
      if (seen.contains(key.label)) {
        _fail(
            "Duplicate object key '${key.label}'; an ambiguous key is never edited",
            key.span.startUnit);
      }
      seen.add(key.label);
      if (_peek != ':') _fail("Expected ':' after an object key");
      final colonStart = _pos;
      _pos++;
      final colon = TokenNode(':', span: _spanTo(colonStart));
      final mid = _readTrivia();
      final value = _parseValue();
      final comma = _parseComma();
      final trailing = _readSameLineTrivia();
      final member = MemberNode(
        leadingTrivia: pending,
        key: key,
        colon: colon,
        midTrivia: mid,
        value: value,
        comma: comma,
        trailingTrivia: trailing,
        span: _entrySpan(pending, key.span.startUnit, value.span.endUnit, comma, trailing),
      );
      _attachEntryComments(pending, mid, trailing, value, member);
      members.add(member);
    }
  }

  ArrayNode _parseArray() {
    final start = _pos;
    _pos++;
    final open = TokenNode('[', span: _spanTo(start, start + 1));
    final afterOpen = _readSameLineTrivia();
    final items = <ItemNode>[];
    while (true) {
      final pending = _readTrivia();
      if (_peek == ']') {
        final closeStart = _pos;
        _pos++;
        final close = TokenNode(']', span: _spanTo(closeStart));
        final node = ArrayNode(
          open: open,
          afterOpen: afterOpen,
          items: items,
          beforeClose: pending,
          close: close,
          span: _spanTo(start),
        );
        for (final t in pending) {
          if (t is CommentNode) t._attach(CommentRole.blockEnd, node);
        }
        return node;
      }
      final value = _parseValue();
      final comma = _parseComma();
      final trailing = _readSameLineTrivia();
      final item = ItemNode(
        leadingTrivia: pending,
        value: value,
        comma: comma,
        trailingTrivia: trailing,
        span: _entrySpan(pending, value.span.startUnit, value.span.endUnit, comma, trailing),
      );
      _attachEntryComments(pending, const [], trailing, value, item);
      items.add(item);
    }
  }

  TokenNode? _parseComma() {
    if (_peek != ',') return null;
    final start = _pos;
    _pos++;
    return TokenNode(',', span: _spanTo(start));
  }

  SourceSpan _entrySpan(List<CstNode> leading, int contentStart,
      int contentEnd, TokenNode? comma, List<CstNode> trailing) {
    final startUnit = leading.isNotEmpty ? leading.first.span.startUnit : contentStart;
    var endUnit = comma?.span.endUnit ?? contentEnd;
    if (trailing.isNotEmpty) endUnit = trailing.last.span.endUnit;
    return SourceSpan(
        startUnit, endUnit, offsets.byteOf(startUnit), offsets.byteOf(endUnit));
  }

  void _attachEntryComments(List<CstNode> leading, List<CstNode> mid,
      List<CstNode> trailing, ValueNode value, CstNode entry) {
    for (final t in leading) {
      if (t is CommentNode) t._attach(CommentRole.leading, entry);
    }
    for (final t in mid) {
      if (t is CommentNode) t._attach(CommentRole.mid, entry);
    }
    for (final t in trailing) {
      if (t is CommentNode) t._attach(CommentRole.trailing, entry);
    }
    // Baseline rule: same-line comments right after a container value's
    // opening bracket are owned as `trailing` by the entry holding that
    // value, not by the container. They stay physically inside the
    // container (the tree must remain a partition of the
    // source), so only the ownership annotation moves.
    final List<CstNode> openingSlot = switch (value) {
      final ObjectNode o => o.afterOpen,
      final ArrayNode a => a.afterOpen,
      final ValueNode _ => const <CstNode>[],
    };
    for (final t in openingSlot) {
      if (t is CommentNode) t._attach(CommentRole.trailing, entry);
    }
  }

  KeyNode _parseKey() {
    if (_pos >= text.length) _fail('Expected an object key');
    final c = text[_pos];
    if (c == '"' || c == "'") {
      final s = _parseString();
      return KeyNode(s.raw, s.value, quoted: true, span: s.span);
    }
    final start = _pos;
    while (_pos < text.length && _isKeyCharAt(_pos)) {
      _pos++;
    }
    if (_pos == start) _fail('Expected an object key');
    final raw = text.substring(start, _pos);
    return KeyNode(raw, raw, quoted: false, span: _spanTo(start));
  }

  bool _isKeyCharAt(int i) {
    final c = text.codeUnitAt(i);
    // `_`, `$`, `.` and `-` join the baseline's Unicode alphanumeric
    // key characters.
    if (c == 0x5F || c == 0x24 || c == 0x2E || c == 0x2D) return true;
    return _alnum.hasMatch(text[i]);
  }

  StringNode _parseString() {
    final start = _pos;
    final quote = text[_pos];
    _pos++;
    final chunks = StringBuffer();
    var hasTpl = false;
    while (true) {
      if (_pos >= text.length) _fail('Unterminated string', start);
      final c = text[_pos];
      if (c == quote) {
        _pos++;
        break;
      }
      if (_isLineBreak(text.codeUnitAt(_pos))) {
        _fail('Unescaped line break in string');
      }
      if (c == r'\') {
        chunks.write(_parseEscape());
        continue;
      }
      if (!hasTpl && _startsWith('\${') && _placeholder.matchAsPrefix(text, _pos) != null) {
        hasTpl = true;
      }
      chunks.write(c);
      _pos++;
    }
    return StringNode(
      raw: text.substring(start, _pos),
      value: chunks.toString(),
      hasPlaceholder: hasTpl,
      span: _spanTo(start),
    );
  }

  String _parseEscape() {
    _pos++; // consume the backslash
    if (_pos >= text.length) _fail('Dangling escape character');
    final c = text[_pos];
    _pos++;
    if (c == 'u') {
      if (_pos + 4 > text.length || !_hex4.hasMatch(text.substring(_pos, _pos + 4))) {
        _fail('Malformed \\u escape');
      }
      final code = int.parse(text.substring(_pos, _pos + 4), radix: 16);
      _pos += 4;
      return String.fromCharCode(code);
    }
    if (c == 'x') {
      // The baseline crashes on non-hex digits here; rejecting cleanly
      // keeps the accept/reject outcome identical.
      if (_pos + 2 > text.length || !_hex2.hasMatch(text.substring(_pos, _pos + 2))) {
        _fail('Malformed \\x escape');
      }
      final code = int.parse(text.substring(_pos, _pos + 2), radix: 16);
      _pos += 2;
      return String.fromCharCode(code);
    }
    if (_isLineBreak(text.codeUnitAt(_pos - 1))) {
      if (c == '\r' && _pos < text.length && text[_pos] == '\n') _pos++;
      return '';
    }
    switch (c) {
      case 'n':
        return '\n';
      case 't':
        return '\t';
      case 'r':
        return '\r';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case 'v':
        return '\v';
      case '0':
        // Dart has no `\0` escape: '\0' is the character "0". The baseline
        // maps the source escape \0 to U+0000.
        return '\x00';
      case r'\':
        return r'\';
      case "'":
        return "'";
      case '"':
        return '"';
      case '/':
        return '/';
      default:
        _fail('Unsupported escape sequence \\$c');
    }
  }

  TemplateNode _parseTemplate() {
    final start = _pos;
    final end = text.indexOf('}', _pos + 2);
    if (end < 0) _fail('Unterminated template token', start);
    final inner = text.substring(start + 2, end);
    _pos = end + 1;
    final match = _templateInner.firstMatch(inner);
    if (match == null) {
      _fail('Unsupported template token; only \${VAR} and \${VAR:-default} are supported', start);
    }
    return TemplateNode(
      raw: text.substring(start, _pos),
      name: match.group(1)!,
      defaultText: match.group(2),
      span: _spanTo(start),
    );
  }

  ValueNode _parseLiteral() {
    final start = _pos;
    while (_pos < text.length) {
      final c = text.codeUnitAt(_pos);
      if (_isWhitespace(c) ||
          c == 0x2C || // ,
          c == 0x3A || // :
          c == 0x7B || // {
          c == 0x7D || // }
          c == 0x5B || // [
          c == 0x5D || // ]
          _isLineBreak(c)) {
        break;
      }
      if (_startsWith('\${')) break;
      _pos++;
    }
    final raw = text.substring(start, _pos);
    if (raw.isEmpty) _fail('Expected a value');
    switch (raw) {
      case 'true':
        return BooleanNode(raw: raw, value: true, span: _spanTo(start));
      case 'false':
        return BooleanNode(raw: raw, value: false, span: _spanTo(start));
      case 'null':
        return NullNode(raw: raw, span: _spanTo(start));
    }
    if (raw == 'undefined' || raw == 'True' || raw == 'False') {
      _fail("Unsupported literal '$raw'", start);
    }
    if (!_number.hasMatch(raw)) _fail("Invalid value token '$raw'", start);
    return NumberNode(raw: raw, value: _toNumber(raw, start), span: _spanTo(start));
  }

  Object _toNumber(String raw, int start) {
    if (raw == 'Infinity' || raw == '+Infinity' || raw == '-Infinity') {
      _fail("Number '$raw' is not portable: non-finite", start);
    }
    if (raw == 'NaN') {
      _fail("Number '$raw' is not portable: not a number", start);
    }
    final lower = raw.toLowerCase();
    if (lower.startsWith('0x') || lower.startsWith('-0x') || lower.startsWith('+0x')) {
      return int.tryParse(raw) ?? BigInt.parse(raw);
    }
    if (raw.contains('.') || raw.contains('e') || raw.contains('E')) {
      return double.parse(raw);
    }
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    try {
      return BigInt.parse(raw);
    } on FormatException {
      // e.g. '+NaN': shape-matched but not an integer; the baseline
      // rejects it as not portable.
      _fail("Number '$raw' is not portable", start);
    }
  }
}
