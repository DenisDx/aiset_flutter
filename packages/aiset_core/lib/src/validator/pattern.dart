part of 'validator.dart';

/// The accepted pattern length when the caller passes no profile
/// (`docs/grammars.md` §1.4, `SPEC.md` amendment 26).
const int defaultMaxPatternLength = 512;

/// Why a regular expression is outside the accepted dialect
/// (`docs/grammars.md` §1.2 and §1.3).
enum PatternRejection {
  /// The construct compiles in this product's engine but the accepted
  /// dialect excludes it, or the other engine cannot compile it so no
  /// file using it is interoperable. Reported when a value is validated,
  /// as the validation issue `pattern` (`docs/grammars.md` §1.3).
  outsideDialect,

  /// The pattern is longer than the accepted limit
  /// (`docs/grammars.md` §1.4). Reported as `pattern_length`.
  tooLong,
}

/// The outcome of checking one pattern against the accepted dialect.
final class PatternCheck {
  /// Creates a check outcome.
  const PatternCheck._(this.ok, this.rejection, this.detail);

  /// The pattern is inside the accepted dialect.
  const PatternCheck.accepted() : this._(true, null, null);

  /// The pattern is refused, with the [reason] and a short [detail]
  /// naming the construct (never the matched value).
  const PatternCheck.rejected(PatternRejection reason, String detail)
      : this._(false, reason, detail);

  /// Whether the pattern is accepted.
  final bool ok;

  /// Why the pattern was refused, or `null` when accepted.
  final PatternRejection? rejection;

  /// The construct that caused the rejection, for the
  /// issue message.
  final String? detail;
}

/// Checks [pattern] against the accepted dialect of `docs/grammars.md` §1.
///
/// This is the validation-layer gate, and it is a whitelist:
/// §1.1 fixes the accepted constructs (everything else is outside the dialect by
/// §1.2's preamble), so the scan accepts exactly the §1.1 forms
/// and refuses anything the two engines do not agree on in syntax and meaning.
///
/// A pattern this product's engine cannot compile never reaches here:
/// it is the `INVALID_PATTERN` descriptor issue produced by the descriptor
/// compiler (`docs/grammars.md` §1.3, first row). The scan therefore reports:
///
/// * the §1.2 constructs that do compile here — lookarounds, numeric
///   backreferences `\1`–`\99`, named groups and named backreferences in
///   either spelling, replacement-spelling group references, POSIX
///   classes, the Python anchors `\A`/`\Z`, Unicode property classes,
///   inline flags in scoped form, and any escape outside the §1.1 list;
/// * the §1.5 matching-budget decision: a pattern whose nested
///   unbounded repetition can make matching explode is refused before it
///   is run, because a pure-Dart synchronous match can promise no timeout
///   (`SPEC.md` amendment 26);
/// * the §1.4 length, counted in Unicode code points.
///
/// The shorthand classes `\d \w \s \b` and their negations are accepted
/// (§1.1): their ASCII-vs-Unicode meaning on non-ASCII text is a value-level
/// match outcome the document records, not a construct the dialect rejects.
PatternCheck checkPatternDialect(String pattern,
    {int maxPatternLength = defaultMaxPatternLength}) {
  if (pattern.runes.length > maxPatternLength) {
    return const PatternCheck.rejected(
        PatternRejection.tooLong, 'the pattern exceeds the accepted length');
  }
  final unsafe = _nestedUnboundedRepetition(p: pattern);
  if (unsafe) {
    return const PatternCheck.rejected(PatternRejection.outsideDialect,
        'an unbounded repetition of a group that repeats unboundedly');
  }
  return _scanPattern(pattern);
}

/// §1.5: whether [pattern] holds `*`, `+` or `{n,}` applied to a group that
/// already repeats unboundedly inside — the shape that makes a synchronous
/// match explosive. One side of it is already refused by
/// the §1.2 rows (backreferences, lookarounds, conditionals); this is
/// the residue the accepted set still allows.
bool _nestedUnboundedRepetition({required String p}) {
  var i = 0;
  var inClass = false;
  while (i < p.length) {
    final c = p[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (inClass) {
      if (c == ']') inClass = false;
      i++;
      continue;
    }
    if (c == '[') {
      inClass = true;
      i++;
      if (i < p.length && p[i] == '^') i++;
      if (i < p.length && p[i] == ']') i++;
      continue;
    }
    final rangeEnd = c == '{' ? _openRangeEnd(p, i) : null;
    final unbounded = c == '*' || c == '+' || rangeEnd != null;
    if (!unbounded) {
      i++;
      continue;
    }
    var after = rangeEnd ?? i + 1;
    if (after < p.length && p[after] == '?') after++; // lazy suffix
    final start = _atomStart(p, i);
    if (start != null && p[start] == '(') {
      final inner = start + 1;
      final innerEnd = i - 1; // the ')' before the quantifier
      if (innerEnd > inner && _subtreeHasUnbounded(p, inner, innerEnd)) return true;
    }
    i = after;
  }
  return false;
}

/// A single left-to-right pass that finds the first construct outside the
/// accepted dialect. Metacharacters are all ASCII, so scanning code
/// units is safe.
PatternCheck _scanPattern(String p) {
  final n = p.length;
  var i = 0;
  var inClass = false;
  while (i < n) {
    final c = p[i];
    if (c == r'\') {
      // A dangling backslash is refused by the engine at
      // descriptor compile time; it is not a dialect decision.
      if (i + 1 >= n) return const PatternCheck.accepted();
      final escape = _classifyEscape(p, i, inClass: inClass);
      if (escape != null) return escape;
      i += _escapeLength(p, i);
      continue;
    }
    if (inClass) {
      if (c == ']') {
        inClass = false;
        i++;
        continue;
      }
      i++;
      continue;
    }
    if (c == '[') {
      // A POSIX class (`docs/grammars.md` §1.2): the engines read it as a set
      // of literal characters with different results.
      if (i + 2 < n && p[i + 1] == '[' && p[i + 2] == ':') {
        return const PatternCheck.rejected(
            PatternRejection.outsideDialect, 'a POSIX character class');
      }
      inClass = true;
      i++;
      if (i < n && p[i] == '^') i++;
      if (i < n && p[i] == ']') {
        // `[]a]` / `[^]]`: Python reads the first `]` as a member,
        // this engine as the end of the class, so the two
        // disagree on what the pattern means. Outside
        // the §1.1 class grammar.
        return const PatternCheck.rejected(PatternRejection.outsideDialect,
            'a class whose first bracket the engines read differently');
      }
      continue;
    }
    if (c == '(') {
      final group = _classifyGroup(p, i);
      if (group != null) return group;
      i++;
      continue;
    }
    if (c == '{') {
      // A brace that does not open a valid `{n}`/`{n,}`/`{n,m}`
      // quantifier is a literal on both engines (`a{2,3` matches itself
      // verbatim in each). A digit-led brace that the engine refused
      // is unreachable here: it failed descriptor compilation.
      final length = _braceQuantifierLength(p, i);
      i += (length == 0 ? 1 : length);
      continue;
    }
    i++;
  }
  return const PatternCheck.accepted();
}

/// The characters that may be escaped literally in either engine.
const String _literalEscapeChars = 'nrtfv0abef';

/// Classifies the `\` escape at [start], or returns `null` when the escape is
/// inside the dialect. Inside a character class the accepted set is
/// §1.1's classes and literal escapes plus the class escapes both
/// engines agree on; outside, the §1.1 anchor set applies.
PatternCheck? _classifyEscape(String p, int start, {required bool inClass}) {
  final e = p[start + 1];
  switch (e) {
    case 'd':
    case 'D':
    case 'w':
    case 'W':
    case 's':
    case 'S':
      // Portable shorthand classes (§1.1).
      return null;
    case 'b':
      // A word boundary outside a class; inside one both engines read it as
      // the backspace character. Either reading is agreed.
      return null;
    case 'B':
      // The negated word boundary is §1.1 anchor syntax; inside a
      // class it is a bare literal 'B' on both engines.
      return inClass ? null : null;
    case 'A':
    case 'Z':
      return const PatternCheck.rejected(
          PatternRejection.outsideDialect, 'a Python-only anchor');
    case 'p':
    case 'P':
      return const PatternCheck.rejected(PatternRejection.outsideDialect,
          'a Unicode property class the engines read differently');
    case 'k':
      // `\k<name>`: this engine reads a named backreference, the baseline
      // engine a literal k (§1.2).
      return const PatternCheck.rejected(PatternRejection.outsideDialect,
          'a named backreference the engines read differently');
    case r'g':
      // `\g<name>`: valid only in a Python replacement template, not in a
      // Python pattern; here the engine reads a literal g (§1.2).
      return const PatternCheck.rejected(PatternRejection.outsideDialect,
          'a group reference in replacement spelling');
    default:
      final code = e.codeUnitAt(0);
      if (code >= 0x31 && code <= 0x39) {
        // `\1` … `\99` (§1.2). `\0` stays with the accepted literal escapes
        // (NUL, or the leading zero of a legacy octal the engines read alike).
        return const PatternCheck.rejected(
            PatternRejection.outsideDialect, 'a numeric backreference');
      }
      if (e == 'u') {
        if (start + 5 < p.length && _isHex4(p.substring(start + 2, start + 6))) {
          return null;
        }
        return _rejectedEscapeForm();
      }
      if (e == 'x') {
        if (start + 3 < p.length && _isHex(p.substring(start + 2, start + 4))) {
          return null;
        }
        return _rejectedEscapeForm();
      }
      if (inClass && code >= 0x30 && code <= 0x37) {
        // An octal escape inside a class: both engines read `[\1]` and `[\0]`
        // as the control character, identically. Accepted; the digit-led
        // forms outside a class stay refused as `\1`–`\99`
        // above because there the same text is a backreference.
        return null;
      }
      if (_literalEscapeChars.contains(e)) return null; // \n \r \t \f \v \0 \a \b \e \f
      final letter = _isAsciiLetter(code);
      if (letter) {
        // An alphabetic escape outside §1.1: at least one engine reads it
        // specially (Python's `\N{…}`, `\Q…\E`, `\e`, `\a`)
        // or refuses it outright; neither reading is portable.
        return const PatternCheck.rejected(PatternRejection.outsideDialect,
            'an escape sequence the engines read differently');
      }
      // An escaped non-letter (`\.`, `\{`, `\(`, `\/`, `\\`, an escaped space,
      // an escaped astral character): a literal in both engines (§1.1).
      return null;
  }
}

PatternCheck _rejectedEscapeForm() => const PatternCheck.rejected(
    PatternRejection.outsideDialect, 'an incomplete character escape');

bool _isAsciiLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

bool _isHex(String s) =>
    s.length == 2 &&
    s.runes.every((r) =>
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x41 && r <= 0x46) ||
        (r >= 0x61 && r <= 0x66));

bool _isHex4(String s) =>
    s.length == 4 &&
    s.runes.every((r) =>
        (r >= 0x30 && r <= 0x39) ||
        (r >= 0x41 && r <= 0x46) ||
        (r >= 0x61 && r <= 0x66));

/// The length in code units of the escape starting at [start].
int _escapeLength(String p, int start) {
  final e = p[start + 1];
  if (e == 'u') {
    return (start + 5 < p.length && _isHex4(p.substring(start + 2, start + 6)))
        ? 6
        : 2;
  }
  if (e == 'x') {
    return (start + 3 < p.length && _isHex(p.substring(start + 2, start + 4)))
        ? 4
        : 2;
  }
  // A legacy octal consumes its remaining octal digits (`\010`, `\7`).
  final code = e.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x37) {
    var len = 2;
    while (start + len < p.length) {
      final d = p.codeUnitAt(start + len);
      if (d < 0x30 || d > 0x37) break;
      len++;
      if (len == 4) break; // at most three digits after the backslash
    }
    return len;
  }
  return 2;
}

/// The length of the quantifier brace run at [i], or `0` when the brace
/// is a literal. A `{` the engine reads as a literal must advance as one so
/// its digits are not re-examined as an escape or a class.
int _braceQuantifierLength(String p, int i) {
  final match = RegExp(r'^\{\d+(,\d*)?\}?').matchAsPrefix(p.substring(i));
  if (match == null) return 0;
  return match.end;
}

/// The end offset of an unbounded `{n,}` range starting at [i], or `null`.
int? _openRangeEnd(String p, int i) {
  final m = RegExp(r'^\{\d+,\}').matchAsPrefix(p.substring(i));
  return m == null ? null : i + m.end;
}

/// Whether the atom in [p] between [start] and [end] repeats unboundedly
/// somewhere inside it.
bool _subtreeHasUnbounded(String p, int start, int end) {
  var i = start;
  var inClass = false;
  while (i < end) {
    final c = p[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (inClass) {
      if (c == ']') inClass = false;
      i++;
      continue;
    }
    if (c == '[') {
      inClass = true;
      i++;
      continue;
    }
    if (c == '*' || c == '+') return true;
    if (c == '{') {
      final e = _openRangeEnd(p, i);
      if (e != null) {
        i = e;
        continue;
      }
    }
    i++;
  }
  return false;
}

/// The start of the atom ending just before [quantifierIndex], or `null`.
int? _atomStart(String p, int quantifierIndex) {
  var i = quantifierIndex - 1;
  if (i < 0) return null;
  // A lazy '?' belongs to the quantifier, not to the atom.
  if (p[i] == '?' && i > 0 && (p[i - 1] == '*' || p[i - 1] == '+' || p[i - 1] == '}')) {
    i--;
  }
  if (p[i] == '}') {
    final open = p.lastIndexOf('{', i);
    if (open < 0) return null;
    i = open - 1;
  }
  if (i < 0) return null;
  if (p[i] == ')') {
    var depth = 0;
    for (var j = i; j >= 0; j--) {
      final c = p[j];
      if (c == ')') {
        depth++;
      } else if (c == '(') {
        depth--;
        if (depth == 0) return j;
      }
    }
    return null;
  }
  if (p[i] == ']') {
    var j = i;
    while (j >= 0 && p[j] != '[') {
      j--;
    }
    return j < 0 ? null : j;
  }
  if (p[i] == r'\' && i > 0 && p[i - 1] == r'\') return i - 1;
  return i;
}

/// Classifies a group opening at [start], or returns `null` for a group in
/// the dialect (a plain capture or a non-capturing `(?:`).
PatternCheck? _classifyGroup(String p, int start) {
  if (start + 1 >= p.length || p[start + 1] != '?') return null;
  if (start + 2 >= p.length) return null;
  final kind = p[start + 2];
  if (kind == ':') {
    // `(?:` is the plain non-capturing group of `docs/grammars.md` §1.1;
    // an inline flag inside the group is a separate form handled below.
    return null;
  }
  if (kind == '=' || kind == '!') {
    return const PatternCheck.rejected(
        PatternRejection.outsideDialect, 'a lookaround');
  }
  if (kind == '<') {
    final next = start + 3 < p.length ? p[start + 3] : '';
    if (next == '=' || next == '!') {
      return const PatternCheck.rejected(
          PatternRejection.outsideDialect, 'a lookaround');
    }
    // (?<name>: this engine compiles a named group, the baseline engine
    // cannot (§1.2: "Python cannot compile it, so no file using it is
    // interoperable").
    return const PatternCheck.rejected(PatternRejection.outsideDialect,
        'a named group the baseline engine cannot compile');
  }
  if (_scopedInlineFlag(p, start)) {
    // A scoped inline flag `(?flags:…)`. This engine compiles the scoped
    // form (a bare `(?i)` it cannot compile is caught by the descriptor
    // compiler as INVALID_PATTERN). An inline flag changes matching semantics
    // invisibly across engines, so it is outside the dialect
    // (`docs/grammars.md` §1.2 inline-flag row, scoped form included).
    return const PatternCheck.rejected(
        PatternRejection.outsideDialect, 'an inline flag');
  }
  // `(?P<name>`, `(?P=name)`, `(?#comment)` and `(?(cond)` are all
  // constructs this engine cannot compile, so the descriptor compiler has
  // already refused them as INVALID_PATTERN (§1.2). Reaching the scan with one
  // is a defensive path, refused rather than guessed at.
  return const PatternCheck.rejected(PatternRejection.outsideDialect,
      'a group construct outside the accepted dialect');
}

/// Whether the group at [start] opens a scoped inline flag `(?flags:`:
/// one or more inline-flag letters (with optional `-` toggles)
/// followed by `:`. The plain non-capturing `(?:` is not a flag run and was
/// already returned as accepted by the caller.
bool _scopedInlineFlag(String p, int start) {
  // Python's inline flags (`docs/grammars.md` §1.2 inline-flag row).
  const flagLetters = 'aiLmsux';
  var i = start + 2;
  var sawFlag = false;
  while (i < p.length && (flagLetters.contains(p[i]) || p[i] == '-')) {
    if (p[i] != '-') sawFlag = true;
    i++;
  }
  return sawFlag && i < p.length && p[i] == ':';
}

/// Compiles [pattern] with this product's regex engine.
///
/// A pattern that does not compile is the `INVALID_PATTERN` descriptor
/// issue (`docs/grammars.md` §1.3, first row), produced by the descriptor
/// compiler (2A). The validator matches only after the dialect check has
/// passed, so a `null` here is a defensive path rather than a reachable
/// one.
RegExp? compilePattern(String pattern) {
  try {
    return RegExp(pattern);
  } on FormatException {
    return null;
  }
}

/// Whether [pattern] matches anywhere in [subject].
///
/// The value constraint is a search, not a full match, on both engines
/// (`SPEC.md` amendment 5, `pattern`).
bool patternMatches(RegExp pattern, String subject) => pattern.hasMatch(subject);

/// Whether [pattern] matches at the start of [key]: the governance
/// semantics for `key_pattern`, the same predicate the descriptor node
/// lookup and the resolver use, so one object answers "which keys do I
/// govern?" identically everywhere (`SPEC_.md` amendment 38, report A25).
bool patternGovernedKey(RegExp pattern, String key) =>
    pattern.matchAsPrefix(key) != null;
