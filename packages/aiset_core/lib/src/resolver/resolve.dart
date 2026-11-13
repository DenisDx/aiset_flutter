part of 'resolver.dart';

/// The marker for a value that is **absent**, as distinct from an explicit
/// null, `false`, zero or the empty string (`SPEC.md` amendment 2, DAT-01).
///
/// A defaulted field is filled only where the document does not carry a value
/// at all; storing `null`, `false`, `0` or `""` is a decision the
/// default must never overwrite.
const Object resolverMissing = _MissingValue();

/// Whether [value] is the absence marker.
bool isMissing(Object? value) => identical(value, resolverMissing);

final class _MissingValue {
  const _MissingValue();
  @override
  String toString() => '<missing>';
}

/// How serious a [ResolutionIssue] is.
enum ResolutionSeverity {
  /// The value cannot be used as resolved.
  error('error'),

  /// The value is usable, but something was not checked.
  warning('warning');

  const ResolutionSeverity(this.label);

  /// The label used in diagnostics and envelopes.
  final String label;
}

/// A problem found while resolving one value.
///
/// [rule] is the stable rule name the write pipeline reports under
/// `VALIDATION_ERROR` (`SPEC.md` amendment 26): `env_not_allowed` or
/// `env_conversion`.
final class ResolutionIssue {
  /// Creates a resolution issue.
  const ResolutionIssue({
    required this.rule,
    required this.path,
    required this.message,
    this.severity = ResolutionSeverity.error,
  });

  /// The stable rule name.
  final String rule;

  /// Pointer of the value the issue is about.
  final String path;

  /// Short human-readable reason. Never contains the value.
  final String message;

  /// Whether the issue blocks the value.
  final ResolutionSeverity severity;

  @override
  String toString() => 'ResolutionIssue($rule at $path): $message';
}

/// The outcome of one resolution: the effective value, the issues found on the
/// way, and the provenance of every value in the subtree.
final class ResolutionResult {
  /// Creates a resolution outcome.
  const ResolutionResult({
    required this.value,
    required this.issues,
    required this.provenance,
  });

  /// The effective value, or [resolverMissing] when nothing is present.
  final Object? value;

  /// Every issue found, in resolution order.
  final List<ResolutionIssue> issues;

  /// Provenance keyed by pointer.
  final Map<String, Provenance> provenance;

  /// The issues that block the value.
  List<ResolutionIssue> get errors =>
      issues.where((i) => i.severity == ResolutionSeverity.error).toList();
}

/// The map view of a stored object value.
///
/// A tree from [Json5Document.storedValue] is already `Map<String, Object?>`;
/// a hand-built literal may be a plain `Map`, and treating it as a scalar
/// would silently skip the whole subtree.
Map<String, Object?>? _asStringMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! Map) return null;
  return <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
}

/// The list view of a stored array value, tolerant of a hand-built
/// literal whose element type is narrower than `Object?`.
List<Object?>? _asList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is! List) return null;
  return [...value];
}

/// Mutable state threaded through one resolution pass.
final class _Pass {
  _Pass(this.resolver, {List<ResolutionIssue>? issues, Map<String, Provenance>? provenance})
      : issues = issues ?? <ResolutionIssue>[],
        provenance = provenance ?? <String, Provenance>{};

  final Resolver resolver;
  final List<ResolutionIssue> issues;
  final Map<String, Provenance> provenance;
}

// -- public entry points -------------------------------------------------

/// Substitutes every placeholder in [text], once.
///
/// The result is data: it is never scanned again, so a value that itself
/// contains `${OTHER}` stays that way. A reference the grammar does not accept
/// is left verbatim rather than partially substituted.
String resolveText(
  String text, {
  required Resolver resolver,
  String path = '',
  List<ResolutionIssue>? issues,
  Map<String, Provenance>? provenance,
}) {
  return _substitute(text, path, _Pass(resolver, issues: issues, provenance: provenance));
}

/// Resolves one stored value against its descriptor [node].
///
/// Containers are walked with the node that governs each
/// member or item; a value under a node that does not allow
/// environment substitution is returned exactly as stored.
Object? resolveValue(
  Object? value,
  DescriptorNode? node,
  Resolver resolver, {
  String path = '',
  List<ResolutionIssue>? issues,
  Map<String, Provenance>? provenance,
}) {
  final pass = _Pass(resolver, issues: issues, provenance: provenance);
  return _resolve(value, node, path, pass);
}

/// The effective snapshot of a whole document: defaults materialized,
/// placeholders resolved, provenance recorded.
///
/// Neither [stored] nor the resolver's layers are modified; the result is a new
/// tree (`SPEC.md` amendment 2).
ResolutionResult buildEffective(
  Object? stored,
  DescriptorNode root,
  Resolver resolver,
) {
  final pass = _Pass(resolver);
  final filled = _withDefaults(stored, root, '', pass);
  final value = _resolve(filled, root, '', pass);
  return ResolutionResult(
      value: value, issues: pass.issues, provenance: pass.provenance);
}

/// The effective value of one subtree, with the descriptor default applied when
/// [stored] is [resolverMissing].
ResolutionResult effectiveAt(
  Object? stored,
  DescriptorNode? node,
  Resolver resolver, {
  String path = '',
}) {
  final pass = _Pass(resolver);
  if (node == null || isMissing(stored)) {
    if (node != null && node.hasDefault) {
      pass.provenance[path.isEmpty ? '/' : path] = const Provenance.defaulted();
      return ResolutionResult(
          value: node.defaultValue, issues: pass.issues, provenance: pass.provenance);
    }
    return ResolutionResult(
        value: resolverMissing, issues: pass.issues, provenance: pass.provenance);
  }
  final filled = _withDefaults(stored, node, path, pass);
  final value = _resolve(filled, node, path, pass);
  return ResolutionResult(
      value: value, issues: pass.issues, provenance: pass.provenance);
}

// -- substitution ---------------------------------------------------------------

/// One parsed placeholder reference.
class _Reference {
  _Reference(this.start, this.end, this.name, this.inlineDefault);
  final int start;
  final int end;
  final String name;

  /// The `:-` fallback text, or `null` when the reference declares none.
  final String? inlineDefault;
}

/// Finds the next reference the grammar accepts, at or after [from].
///
/// A reference is `${NAME}` or `${NAME:-DEFAULT}` where `NAME` is an ASCII
/// identifier and `DEFAULT` holds no `}` and does not open another
/// reference. Anything else is not a reference: the scanner reports where
/// the broken text ends so the caller leaves the whole thing verbatim
/// instead of substituting a fragment of it (`SPEC_.md` 38, report A23).
_Reference? _scanReference(String text, int from) {
  var i = from;
  while (i < text.length) {
    if (text.codeUnitAt(i) == 0x24 && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x7B) {
      final nameStart = i + 2;
      var j = nameStart;
      while (j < text.length && _isNameChar(text.codeUnitAt(j), first: j == nameStart)) {
        j++;
      }
      final name = text.substring(nameStart, j);
      final closer = text.indexOf('}', j);
      if (name.isEmpty) {
        i = closer < 0 ? text.length : closer + 1;
        continue;
      }
      if (j < text.length && text.codeUnitAt(j) == 0x7D) {
        return _Reference(i, j + 1, name, null);
      }
      if (j + 1 < text.length && text.codeUnitAt(j) == 0x3A && text.codeUnitAt(j + 1) == 0x2D) {
        final bodyStart = j + 2;
        if (closer < 0) {
          i = text.length;
          continue;
        }
        final body = text.substring(bodyStart, closer);
        if (body.contains(r'${')) {
          // A nested reference is not a value this grammar can
          // express; skip the whole construct instead of eating a prefix of it.
          final outer = text.indexOf('}', closer + 1);
          i = outer < 0 ? text.length : outer + 1;
          continue;
        }
        return _Reference(i, closer + 1, name, body);
      }
      i = closer < 0 ? text.length : closer + 1;
      continue;
    }
    i++;
  }
  return null;
}

bool _isNameChar(int unit, {required bool first}) =>
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    (!first && unit >= 0x30 && unit <= 0x39);

/// Whether [text] holds at least one reference.
bool _hasReference(String text) => _scanReference(text, 0) != null;

String _substitute(String text, String path, _Pass pass) {
  final out = StringBuffer();
  var cursor = 0;
  final contributed = <String>{}; // ordered set: one variable twice is one source
  var best = VariableSource.empty;
  var rank = _sources.length;
  while (true) {
    final found = _scanReference(text, cursor);
    if (found == null) break;
    out.write(text.substring(cursor, found.start));
    final lookup = pass.resolver.lookup(found.name, inlineDefault: found.inlineDefault);
    out.write(lookup.value);
    contributed.add(found.name);
    final position = _sources.indexOf(lookup.source);
    if (position >= 0 && position < rank) {
      rank = position;
      best = lookup.source;
    }
    cursor = found.end;
  }
  out.write(text.substring(cursor));
  if (contributed.isNotEmpty) {
    pass.provenance[path] = contributed.length == 1
        ? Provenance.environment(contributed.first, best)
        : Provenance.fromVariables(contributed.toList(), best);
  }
  return out.toString();
}

/// Sources in precedence order; the first entry is the strongest.
const List<VariableSource> _sources = [
  VariableSource.override,
  VariableSource.environment,
  VariableSource.dotenv,
  VariableSource.inlineDefault,
  VariableSource.empty,
];

// -- walking the stored tree ------------------------------------------------------

Object? _resolve(Object? value, DescriptorNode? node, String path, _Pass pass) {
  if (value is TemplateRef) return _resolveTemplate(value, node, path, pass);
  if (value is String) {
    if (!_hasReference(value)) {
      _recordFile(path, pass);
      return value;
    }
    if (node == null || !node.envAllowed) {
      _recordFile(path, pass);
      return value;
    }
    final resolved = _substitute(value, path, pass);
    final convert = node.envConvert;
    if (convert != null && convert != 'string') {
      return _convert(resolved, node, path, pass, convert: convert);
    }
    return resolved;
  }
  final members = _asStringMap(value);
  if (members != null && node != null) {
    return <String, Object?>{
      for (final entry in members.entries)
        entry.key: _resolveMember(entry.value, node, entry.key, path, pass),
    };
  }
  final items = _asList(value);
  if (items != null && node != null) {
    return [
      for (var index = 0; index < items.length; index++)
        _resolve(items[index], _arrayItemNode(node, index), '$path/$index', pass),
    ];
  }
  _recordFile(path, pass);
  return value;
}

/// Resolves one member of an object, choosing the node that governs the key.
Object? _resolveMember(
    Object? value, DescriptorNode node, String key, String path, _Pass pass) {
  final childPath = '$path/${escapePointerToken(key)}';
  final declared = node.children?[key];
  if (declared != null) return _resolve(value, declared, childPath, pass);

  final candidates = <DescriptorNode>[
    for (final option in node.optionNodes ?? const <DescriptorNode>[])
      if (option.type == 'object' && option.children != null && option.children!.containsKey(key))
        option.children![key]!,
  ];
  if (candidates.isNotEmpty) {
    if (candidates.length == 1 || !_carriesReference(value)) {
      final shaped = candidates.where((c) => _accepts(c, _shapeOf(value))).toList();
      return _resolve(value, (shaped.isEmpty ? candidates : shaped).first, childPath, pass);
    }
    // The value is a reference, so its type is only known after
    // substitution. Trying each candidate keeps a document the
    // descriptor permits from being refused by the first
    // alternative that happens to declare the key
    // (`SPEC_.md` 38, report A26).
    List<ResolutionIssue>? fallbackIssues;
    Map<String, Provenance>? fallbackProvenance;
    Object? fallbackValue;
    for (final candidate in candidates) {
      final trial = _Pass(pass.resolver);
      final resolved = _resolve(value, candidate, childPath, trial);
      if (!trial.issues.any((i) => i.rule == 'env_conversion')) {
        pass.issues.addAll(trial.issues);
        pass.provenance.addAll(trial.provenance);
        return resolved;
      }
      fallbackIssues ??= trial.issues;
      fallbackProvenance ??= trial.provenance;
      fallbackValue = resolved;
    }
    pass.issues.addAll(fallbackIssues!);
    pass.provenance.addAll(fallbackProvenance!);
    return fallbackValue;
  }

  if (!_governsKey(node, key)) {
    // The descriptor does not govern this key, so nothing here is a
    // template to substitute: resolution continues with no node,
    // which still reports a bare placeholder that can never be
    // answered (`SPEC_.md` 38, report A25).
    return _resolve(value, null, childPath, pass);
  }
  return _resolve(value, node.additionalChildren, childPath, pass);
}

/// Whether an object governs undeclared [key] through `additional_children`.
bool _governsKey(DescriptorNode node, String key) {
  if (node.additionalChildren == null) return false;
  final allowed = node.keyEnum;
  if (allowed != null && allowed.isNotEmpty && !allowed.contains(key)) return false;
  final pattern = node.keyPattern;
  if (pattern != null && pattern.isNotEmpty && RegExp(pattern).matchAsPrefix(key) == null) {
    return false;
  }
  return true;
}

Object? _resolveTemplate(
    TemplateRef ref, DescriptorNode? node, String path, _Pass pass) {
  if (node == null || !node.envAllowed) {
    pass.issues.add(ResolutionIssue(
        rule: 'env_not_allowed',
        path: path,
        message:
            'Unquoted placeholder requires env.allowed on the descriptor node'));
    return null;
  }
  final lookup = pass.resolver.lookup(ref.name, inlineDefault: ref.defaultText);
  pass.provenance[path] = Provenance.environment(ref.name, lookup.source);
  return _convert(lookup.value, node, path, pass,
      convert: node.envConvert ?? 'string');
}

void _recordFile(String path, _Pass pass) {
  if (path.isEmpty) return;
  // A value the walk did not produce keeps the provenance it already
  // has: a materialized default was not read from the file, and
  // recording it as if it were would collapse two of the six leaf
  // states (`SPEC_.md` 38, report A27).
  pass.provenance.putIfAbsent(path, () => const Provenance.file());
}

DescriptorNode? _arrayItemNode(DescriptorNode node, int index) {
  final options = node.optionNodes;
  if (options != null) {
    if (options.isEmpty) return null;
    return options[index < options.length ? index : options.length - 1];
  }
  return node.itemNode;
}

String _shapeOf(Object? value) => switch (value) {
      final _ when isMissing(value) => 'missing',
      final TemplateRef _ => 'template',
      final bool _ => 'bool',
      final int _ || final BigInt _ => 'int',
      final double _ => 'number',
      final String _ => 'string',
      final List<Object?> _ => 'array',
      final Map<String, Object?> _ => 'object',
      final _ when isMissing(value) => 'missing',
      _ => 'null',
    };

bool _accepts(DescriptorNode node, String shape) {
  if (shape == 'template' || shape == 'null' || node.type == 'any' || node.type == 'union') {
    return true;
  }
  return node.type == shape;
}

bool _carriesReference(Object? value) => switch (value) {
      final TemplateRef _ => true,
      final String s => _hasReference(s),
      _ => false,
    };

// -- conversion -------------------------------------------------------------------

Object? _convert(String value, DescriptorNode node, String path, _Pass pass,
    {String? convert}) {
  final kind = convert ?? node.envConvert ?? 'string';
  if (kind == 'string') return value;
  if (kind == 'bool') {
    if (value == 'true') return true;
    if (value == 'false') return false;
    pass.issues.add(ResolutionIssue(
        rule: 'env_conversion',
        path: path,
        message: "Boolean conversion accepts only 'true' or 'false'"));
    return null;
  }
  final text = value.trim();
  if (text.isEmpty) {
    pass.issues.add(ResolutionIssue(
        rule: 'env_conversion', path: path, message: 'Empty value cannot be converted'));
    return null;
  }
  if (kind == 'int') {
    final parsed = _asciiInteger(text);
    if (parsed == null ||
        parsed > DescriptorGrammar.maxExactInt ||
        parsed < DescriptorGrammar.minExactInt) {
      pass.issues.add(ResolutionIssue(
          rule: 'env_conversion',
          path: path,
          message: 'Value cannot be converted to $kind'));
      return null;
    }
    // Inside the interoperable range the value is an ordinary int.
    if (parsed.isValidInt) return parsed.toInt();
    return parsed;
  }
  final number = _asciiNumber(text);
  if (number == null) {
    pass.issues.add(ResolutionIssue(
        rule: 'env_conversion', path: path, message: 'Value cannot be converted to $kind'));
    return null;
  }
  return number;
}

/// An integer written with ASCII digits only.
///
/// Python's `int()` and `\d` also accept Unicode decimal digits and the
/// underscore grouping of its literal syntax, so the same text means
/// a number there and nothing here. Refusing is the safe direction and is what
/// `docs/grammars.md` §1.1 records for this product
/// (`SPEC_.md` 38, reports A27 and A28).
BigInt? _asciiInteger(String text) {
  if (!RegExp(r'^[+-]?[0-9]+$').hasMatch(text)) return null;
  return BigInt.tryParse(text);
}

/// A finite decimal or exponential number written with ASCII digits.
double? _asciiNumber(String text) {
  if (!RegExp(r'^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$').hasMatch(text)) {
    return null;
  }
  final parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

// -- defaults ---------------------------------------------------------------------

Object? _withDefaults(Object? stored, DescriptorNode? node, String path, _Pass pass) {
  if (node == null) return stored;
  if (isMissing(stored)) {
    if (node.hasDefault) {
      pass.provenance[path.isEmpty ? '/' : path] = const Provenance.defaulted();
      return node.defaultValue;
    }
    return resolverMissing;
  }
  final storedMembers = _asStringMap(stored);
  if (storedMembers != null && node.type == 'object') {
    final result = <String, Object?>{};
    final names = (node.children ?? const <String, DescriptorNode>{}).keys.toSet();
    (node.children ?? const <String, DescriptorNode>{}).forEach((name, child) {
      final childPath = '$path/${escapePointerToken(name)}';
      if (storedMembers.containsKey(name)) {
        result[name] = _withDefaults(storedMembers[name], child, childPath, pass);
      } else {
        final filled = _withDefaults(resolverMissing, child, childPath, pass);
        if (!isMissing(filled)) result[name] = filled;
      }
    });
    storedMembers.forEach((key, value) {
      if (names.contains(key)) return;
      final childPath = '$path/${escapePointerToken(key)}';
      final child = node.additionalChildren;
      // A key the descriptor does not govern is passed through untouched:
      // materializing a default for it would invent a value for a field the
      // grammar forbids (`SPEC_.md` 38, report A25).
      if (child == null || !_governsKey(node, key)) {
        result[key] = value;
        return;
      }
      result[key] = _withDefaults(value, child, childPath, pass);
    });
    return result;
  }
  final storedItems = _asList(stored);
  if (storedItems != null && node.type == 'array') {
    return [
      for (var index = 0; index < storedItems.length; index++)
        _withDefaults(storedItems[index], _arrayItemNode(node, index), '$path/$index', pass),
    ];
  }
  return stored;
}
