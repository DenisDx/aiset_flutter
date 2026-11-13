part of 'validator.dart';

/// Validates a stored value against a compiled descriptor node.
///
/// [validateDocument] is the whole-candidate entry point; [validateValue]
/// checks one value against one node and is the unit
/// the resource limits call before any constraint.
///
/// Validation reads the value and the node tree and never
/// writes to either, and an issue message never carries a value.

/// The outcome of a validation pass: the issues found.
///
/// [valid] is true when no issue has [ValidationSeverity.error]
/// severity. The list is in walk order (structural limits first when
/// [validateDocument] ran them, then the constraint walk).
final class ValidationOutcome {
  /// Creates an outcome.
  const ValidationOutcome._(this.valid, this._issues);

  /// Whether the value satisfies the descriptor.
  final bool valid;

  final List<ValidationIssue> _issues;

  /// Every issue found, error and warning, in walk order.
  List<ValidationIssue> get issues => UnmodifiableListView(_issues);

  @override
  String toString() => 'ValidationOutcome(valid: $valid, ${_issues.length} issues)';
}

/// Validates [value] against a compiled [root] with the default
/// compatibility profile.
///
/// The cheap structural limits run first; if any is violated the
/// result is those issues alone (an over-deep or
/// over-large tree is not walked against every constraint).
/// Otherwise the constraint walk produces the type, null,
/// per-type constraint, `const`/`enum`, key-governance and
/// union issues.
ValidationOutcome validateDocument(Object? value, DescriptorNode root,
        {Limits limits = Limits.defaultProfile}) =>
    _runValidation(value, root, limits);

ValidationOutcome _runValidation(Object? value, DescriptorNode root, Limits limits) {
  final structural = checkLimits(value, limits: limits);
  if (structural.isNotEmpty) {
    return ValidationOutcome._(false, structural);
  }
  final out = <ValidationIssue>[];
  _validateValue(value, root, '', out, limits: limits);
  return ValidationOutcome._(
      !out.any((i) => i.severity == ValidationSeverity.error), out);
}

/// Validates one value against its descriptor node.
///
/// [present] is false for a field that is absent from the
/// object; only the `undeclared_path` and `unresolved_template`
/// checks run before it short-circuits, matching
/// the baseline. [limits] carries the pattern-length bound.
List<ValidationIssue> validateValue(
  Object? value,
  DescriptorNode? node,
  String path, {
  bool present = true,
  Limits limits = Limits.defaultProfile,
}) {
  final out = <ValidationIssue>[];
  _validateValue(value, node, path, out, present: present, limits: limits);
  return out;
}

void _validateValue(
  Object? value,
  DescriptorNode? node,
  String path,
  List<ValidationIssue> out, {
  bool present = true,
  required Limits limits,
}) {
  if (node == null) {
    out.add(ValidationIssue(
        rule: 'undeclared_path',
        path: path,
        message: 'Path is not declared by the descriptor'));
    return;
  }
  if (value is TemplateRef) {
    out.add(ValidationIssue(
        rule: 'unresolved_template',
        path: path,
        message: 'Placeholder must be resolved before validation'));
    return;
  }
  if (!present) return;
  if (node.type == 'any') return; // opaque: no type, null or constraint rule

  if (node.type == 'union') {
    // A null reaches the alternatives here; the
    // baseline reports `nullable` before it ever asks
    // them (PENDING-A35). See _validateUnion.
    _validateUnion(value, node, path, out, limits: limits);
    return;
  }
  if (value == null) {
    if (node.nullable || node.type == 'null') return;
    out.add(ValidationIssue(
        rule: 'nullable', path: path, message: 'Value must not be null'));
    return;
  }
  if (!_typeMatches(node.type, value)) {
    out.add(ValidationIssue(
        rule: 'type',
        path: path,
        message: 'Expected ${node.type}, got ${_kindOf(value)}'));
    return;
  }

  if (node.type == 'int' && !withinExactRange(value)) {
    out.add(ValidationIssue(
        rule: 'exact_range',
        path: path,
        message: 'Integer must be within [$minExactInt, $maxExactInt]'));
  }

  switch (node.type) {
    case 'object':
      _validateObject(_asStringMap(value)!, node, path, out, limits: limits);
    case 'array':
      _validateArray(_asList(value)!, node, path, out, limits: limits);
    case 'string':
      _validateString(value as String, node, path, out, limits: limits);
  }

  if (node.type == 'int' || node.type == 'number') {
    if (node.minimum != null && compareNumbers(value, node.minimum) < 0) {
      out.add(ValidationIssue(
          rule: 'minimum',
          path: path,
          message: 'Must be at least ${node.minimum}'));
    }
    if (node.maximum != null && compareNumbers(value, node.maximum) > 0) {
      out.add(ValidationIssue(
          rule: 'maximum',
          path: path,
          message: 'Must be at most ${node.maximum}'));
    }
  }
  if (node.hasConst && !_sameValue(node.constValue, value)) {
    out.add(ValidationIssue(
        rule: 'const', path: path, message: 'Value differs from the fixed value'));
  }
  final options = node.enumValues;
  if (options != null && !options.any((option) => _sameValue(option, value))) {
    out.add(ValidationIssue(
        rule: 'enum',
        path: path,
        message: 'Value is not one of the allowed values'));
  }
}

void _validateObject(Map<String, Object?> value, DescriptorNode node, String path,
    List<ValidationIssue> out, {required Limits limits}) {
  // The executed baseline re-checks the collection and
  // key-size limits inside the object recursion, so a direct
  // validateValue call on an oversized object reports them at the
  // container. The document walk keeps them, too:
  // checkLimits short-circuits above, so nothing is reported twice.
  if (value.length > limits.maxCollectionSize) {
    out.add(ValidationIssue(
        rule: 'max_collection_size',
        path: path,
        message: 'Object exceeds ${limits.maxCollectionSize} keys'));
  }
  value.forEach((key, item) {
    if (key.runes.length > limits.maxStringLength) {
      out.add(ValidationIssue(
          rule: 'max_string_length', path: path, message: 'Object key is too long'));
    }
    final childPath = '$path/${escapePointerToken(key)}';
    final declared = node.children?[key];
    if (declared != null) {
      _validateValue(item, declared, childPath, out, limits: limits);
      return;
    }
    final additional = node.additionalChildren;
    if (additional == null) {
      out.add(ValidationIssue(
          rule: 'undeclared_field',
          path: childPath,
          message: 'Field is not declared'));
      return;
    }
    // One governance rule for undeclared keys: key_enum and
    // key_pattern are checked together and identically to the
    // descriptor node lookup and the resolver, so an object never governs a
    // key one call site accepts and another rejects
    // (`SPEC_.md` amendment 38, report A25).
    final enumKeys = node.keyEnum;
    if (enumKeys != null && enumKeys.isNotEmpty && !enumKeys.contains(key)) {
      out.add(ValidationIssue(
          rule: 'key_enum', path: childPath, message: 'Key is not in key_enum'));
    }
    final pattern = node.keyPattern;
    if (pattern != null && pattern.isNotEmpty) {
      final check =
          checkPatternDialect(pattern, maxPatternLength: limits.maxPatternLength);
      final compiled = check.ok ? compilePattern(pattern) : null;
      if (!check.ok) {
        out.add(ValidationIssue(
            rule: check.rejection == PatternRejection.tooLong
                ? 'pattern_length'
                : 'pattern',
            path: childPath,
            message: 'Key pattern is ${check.detail}'));
      } else if (compiled == null || !patternGovernedKey(compiled, key)) {
        out.add(ValidationIssue(
            rule: 'key_pattern',
            path: childPath,
            message: 'Key does not match key_pattern'));
      }
    }
    _validateValue(item, additional, childPath, out, limits: limits);
  });
  (node.children ?? const <String, DescriptorNode>{}).forEach((name, child) {
    if (child.required && !value.containsKey(name)) {
      out.add(ValidationIssue(
          rule: 'required',
          path: '$path/${escapePointerToken(name)}',
          message: 'Field is required'));
    }
  });
}

void _validateArray(List<Object?> value, DescriptorNode node, String path,
    List<ValidationIssue> out, {required Limits limits}) {
  if (node.minItems != null &&
      compareNumbers(value.length, node.minItems) < 0) {
    out.add(ValidationIssue(
        rule: 'min_items',
        path: path,
        message: 'Must contain at least ${node.minItems} items'));
  }
  if (node.maxItems != null &&
      compareNumbers(value.length, node.maxItems) > 0) {
    out.add(ValidationIssue(
        rule: 'max_items',
        path: path,
        message: 'Must contain at most ${node.maxItems} items'));
  }
  if (node.uniqueItems == true) {
    outer:
    for (var i = 0; i < value.length; i++) {
      for (var j = i + 1; j < value.length; j++) {
        if (_sameValue(value[i], value[j])) {
          out.add(ValidationIssue(
              rule: 'unique_items',
              path: '$path/$i',
              message: 'Items must be unique'));
          break outer;
        }
      }
    }
  }
  final options = node.optionNodes;
  for (var index = 0; index < value.length; index++) {
    final itemPath = '$path/$index';
    if (options != null) {
      _validateUnion(value[index], node, itemPath, out, limits: limits);
    } else {
      _validateValue(value[index], node.itemNode, itemPath, out, limits: limits);
    }
  }
}

void _validateString(String value, DescriptorNode node, String path,
    List<ValidationIssue> out, {required Limits limits}) {
  final length = value.runes.length; // Unicode code points (docs/grammars.md §1.4)
  if (node.minLength != null && compareNumbers(length, node.minLength) < 0) {
    out.add(ValidationIssue(
        rule: 'min_length',
        path: path,
        message: 'Must be at least ${node.minLength} characters'));
  }
  if (node.maxLength != null && compareNumbers(length, node.maxLength) > 0) {
    out.add(ValidationIssue(
        rule: 'max_length',
        path: path,
        message: 'Must be at most ${node.maxLength} characters'));
  }
  final pattern = node.pattern;
  if (pattern == null || pattern.isEmpty) return; // empty pattern is no constraint
  final check = checkPatternDialect(pattern, maxPatternLength: limits.maxPatternLength);
  if (!check.ok) {
    out.add(ValidationIssue(
        rule: check.rejection == PatternRejection.tooLong ? 'pattern_length' : 'pattern',
        path: path,
        message: 'Pattern is ${check.detail}'));
    return;
  }
  final compiled = compilePattern(pattern);
  if (compiled == null) {
    out.add(ValidationIssue(
        rule: 'pattern', path: path, message: 'The pattern cannot be evaluated'));
    return;
  }
  if (!patternMatches(compiled, value)) {
    out.add(ValidationIssue(
        rule: 'pattern', path: path, message: 'Value does not match the pattern'));
  }
}

void _validateUnion(
    Object? value, DescriptorNode node, String path, List<ValidationIssue> out,
    {required Limits limits}) {
  final options = node.optionNodes ?? const <DescriptorNode>[];
  if (value == null) {
    // Corrected behavior (PENDING-A35): a union admits a null value
    // when one of its alternatives admits null. The executed
    // baseline reports `nullable` for the union node before
    // consulting any alternative, so a union of
    // {null} and {int} still refuses null.
    final admitsNull = options
        .any((o) => o.type == 'null' || o.type == 'any' || o.nullable);
    if (admitsNull) return;
    out.add(ValidationIssue(
        rule: 'nullable', path: path, message: 'Value must not be null'));
    return;
  }
  final fewestList = <ValidationIssue>[];
  var fewestCount = -1;
  for (final option in options) {
    final trial = <ValidationIssue>[];
    _validateValue(value, option, path, trial, limits: limits);
    if (trial.isEmpty) return; // one alternative fits: the value is valid
    if (fewestCount < 0 || trial.length < fewestCount) {
      fewestList
        ..clear()
        ..addAll(trial);
      fewestCount = trial.length;
    }
  }
  final detail = [for (final issue in fewestList.take(3)) '${issue.rule}: ${issue.message}']
      .join('; ');
  out.add(ValidationIssue(
      rule: 'union',
      path: path,
      message:
          'Value matches none of the ${options.length} alternatives${detail.isEmpty ? '' : ' ($detail)'}'));
}

// -- helpers -------------------------------------------------------------------

bool _typeMatches(String type, Object? value) => switch (type) {
      'any' || 'union' => true,
      'string' => value is String,
      'bool' => value is bool,
      'int' => value is int || value is BigInt,
      'number' => value is int || value is BigInt || (value is double && value.isFinite),
      'null' => value == null,
      'object' => value is Map,
      'array' => value is List,
      _ => true,
    };

String _kindOf(Object? value) => switch (value) {
      null => 'null',
      final bool _ => 'bool',
      final int _ || final BigInt _ => 'int',
      final double _ => 'number',
      final String _ => 'string',
      final List<Object?> _ => 'array',
      final Map<String, Object?> _ => 'object',
      final TemplateRef _ => 'template',
      final _ when isMissing(value) => 'missing',
      _ => 'unknown',
    };

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  }
  return null;
}

List<Object?>? _asList(Object? value) {
  if (value is List<Object?>) return value;
  if (value is List) return [...value];
  return null;
}

/// Deep structural equality with exact numbers and no bool/number
/// coercion (`const` and `enum` members stay distinct from
/// `true`/`1`/`1.0`).
///
/// Distinct integers are never merged by a rounding
/// step (`SPEC_.md` amendment 38, report PENDING-A34).
bool _sameValue(Object? expected, Object? actual) {
  if (expected is bool || actual is bool) {
    return expected is bool && actual is bool && expected == actual;
  }
  if (expected == null || actual == null) return expected == null && actual == null;
  if (isNumericValue(expected) && isNumericValue(actual)) {
    return numbersEqual(expected, actual);
  }
  if (expected is String && actual is String) return expected == actual;
  final expectedList = _asList(expected);
  final actualList = _asList(actual);
  if (expectedList != null && actualList != null) {
    return expectedList.length == actualList.length &&
        List.generate(expectedList.length, (i) => i)
            .every((i) => _sameValue(expectedList[i], actualList[i]));
  }
  final expectedMap = _asStringMap(expected);
  final actualMap = _asStringMap(actual);
  if (expectedMap != null && actualMap != null) {
    if (expectedMap.length != actualMap.length) return false;
    return expectedMap.keys.every((key) =>
        actualMap.containsKey(key) && _sameValue(expectedMap[key], actualMap[key]));
  }
  return false;
}
