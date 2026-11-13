part of 'descriptor.dart';

/// Validates descriptor source and reports every grammar problem, without
/// compiling it (`SPEC.md` amendment 5: the development operation).
///
/// [strict] turns unknown-metadata warnings into errors. [knownTemplates]
/// supplies template definitions declared in another file, so a
/// reference to them is not reported as an unknown type.
DescriptorDiagnostic validateDescriptor(
  String source, {
  bool strict = false,
  Map<String, Object?>? knownTemplates,
}) {
  final Json5Document document;
  try {
    document = Json5Document(source, origin: 'descriptor.json5');
  } on Json5ParseException catch (e) {
    return DescriptorDiagnostic(valid: false, issues: [
      DescriptorIssue(
          code: 'DESCRIPTOR_SYNTAX',
          severity: DescriptorSeverity.error,
          path: '',
          message: e.message),
    ]);
  }
  return _diagnose(document.storedValue(), document,
      strict: strict, knownTemplates: knownTemplates);
}

/// Runs every grammar rule over an already parsed descriptor.
///
/// [document] supplies source positions when the data came from a readable
/// document; composed trees have none, and their issues say so rather
/// than pointing into a generated dump.
DescriptorDiagnostic _diagnose(
  Object? data,
  Json5Document? document, {
  required bool strict,
  Map<String, Object?>? knownTemplates,
}) {
  final out = _IssueBuilder();

  // A descriptor document that is not an object is a structure failure. The
  // baseline crashes here instead (report A10); the diagnostic the baseline
  // itself intended to emit is reproduced.
  if (data is! Map<String, Object?>) {
    final position = document == null
        ? null
        : _codePointPosition(document, document.root.span.startUnit);
    return DescriptorDiagnostic(valid: false, issues: [
      DescriptorIssue(
        code: 'DESCRIPTOR_SYNTAX',
        severity: DescriptorSeverity.error,
        path: '',
        message: 'Descriptor root must be an object',
        line: position?.$1,
        column: position?.$2,
      ),
    ]);
  }

  final templates = <String, Object?>{...?knownTemplates};
  _collectTemplates(data, templates);

  _checkEnvelope(data, out);
  final root = data[DescriptorGrammar.rootKey];
  if (root is Map<String, Object?>) {
    _checkNode(root, '/root', out, allowId: false, templates: templates);
  } else {
    out.add('DESCRIPTOR_STRUCTURE', '/root', 'root must be an object node');
  }
  _checkTemplateDuplicates(data, out);
  _checkTemplateReferences(data, templates, out);

  var issues = out.issues;
  if (strict) {
    issues = [
      for (final issue in issues)
        if (issue.code == unknownPropertyCode)
          issue.copyWithSeverity(DescriptorSeverity.error)
        else
          issue,
    ];
  }
  if (document != null) issues = _locateIssues(document, issues);
  return DescriptorDiagnostic(
    valid: !issues.any((i) => i.severity == DescriptorSeverity.error),
    issues: issues,
  );
}

/// The issue code for metadata the shared grammar does not interpret.
const String unknownPropertyCode = 'UNKNOWN_DESCRIPTOR_PROPERTY';

/// The message used for every unknown property, matching the baseline wording.
const String unknownPropertyMessage =
    'Property is not interpreted by the shared settings library';

// -- envelope ---------------------------------------------------------------

void _checkEnvelope(Map<String, Object?> data, _IssueBuilder out) {
  final version = data[DescriptorGrammar.versionKey];
  if (version is! String) {
    out.add('DESCRIPTOR_VERSION', '/${DescriptorGrammar.versionKey}',
        'descriptor_version is required');
  } else if (version != descriptorVersion) {
    out.add('DESCRIPTOR_VERSION', '/${DescriptorGrammar.versionKey}',
        "Unsupported descriptor version '$version'; recognized: '$descriptorVersion'");
  }
  for (final key in ['project', 'config_version']) {
    if (data.containsKey(key) && data[key] is! String) {
      out.add('DESCRIPTOR_STRUCTURE', '/$key', '$key must be a string');
    }
  }
  if (!data.containsKey(DescriptorGrammar.rootKey)) {
    out.add('DESCRIPTOR_STRUCTURE', '/${DescriptorGrammar.rootKey}', 'root is required');
  }
  // Unknown envelope metadata is reported too. The baseline checks node
  // properties only, so a stray key at the top level passes unnoticed
  // (report A14), while SPEC.md amendment 5 requires the warning.
  for (final key in data.keys) {
    if (!DescriptorGrammar.envelopeKeys.contains(key)) {
      out.warn(unknownPropertyCode, '/$key', unknownPropertyMessage);
    }
  }
}

// -- one node ---------------------------------------------------------------

void _checkNode(
  Map<String, Object?> node,
  String path,
  _IssueBuilder out, {
  required bool allowId,
  required Map<String, Object?> templates,
}) {
  for (final entry in node.entries) {
    final key = entry.key;
    final declared = DescriptorGrammar.propertyTypes[key];
    if (declared != null) {
      if (key == 'type' || key == 'default' || key == 'const') continue;
      if (key == 'description' || key == 'title') {
        readDescriptorText(
          entry.value,
          path: '$path/$key',
          report: (issuePath, message, wrongValueType) => out.add(
              wrongValueType ? 'INVALID_PROPERTY_TYPE' : 'INVALID_STRUCTURE',
              issuePath,
              message),
        );
        continue;
      }
      if (!matchesPropertyType(declared, entry.value)) {
        out.add('INVALID_PROPERTY_TYPE', '$path/$key',
            "Property '$key' has an unsupported value type");
      }
    } else if (key == 'default' || key == 'const') {
      continue;
    } else {
      out.warn(unknownPropertyCode, '$path/$key', unknownPropertyMessage);
    }
  }

  final declaredType = node['type'];
  if (declaredType is! String) {
    out.add('DESCRIPTOR_STRUCTURE', '$path/type', 'type is required');
    return;
  }
  final nodeType = _effectiveType(declaredType, templates);

  if (node['required'] == true && node.containsKey('default')) {
    out.add('INVALID_STRUCTURE', '$path/default',
        'required with default is invalid: required means explicitly present');
  }
  if (node.containsKey('enum') && node.containsKey('const')) {
    out.add('INVALID_STRUCTURE', '$path/const',
        'enum with const is invalid: one fixed value cannot also list alternatives');
  }
  final apply = node['apply'];
  if (apply != null && apply is! String) {
    out.add('INVALID_PROPERTY_VALUE', '$path/apply',
        'apply must be one of ${DescriptorGrammar.applyValues.join(', ')}');
  } else if (apply is String && !DescriptorGrammar.applyValues.contains(apply)) {
    out.add('INVALID_PROPERTY_VALUE', '$path/apply',
        'apply must be one of ${DescriptorGrammar.applyValues.join(', ')}');
  }
  if (!allowId && node.containsKey('id')) {
    out.add('INVALID_ID', '$path/id',
        "id is accepted only as a direct entry of an object's children mapping");
  }
  final typedef = node['typedef'];
  if (typedef != null && typedef is! String) {
    out.add('INVALID_PROPERTY_TYPE', '$path/typedef', 'typedef must be a string');
  } else if (typedef is String && DescriptorGrammar.primitiveTypes.contains(typedef)) {
    out.add('TEMPLATE_SHADOWS_PRIMITIVE', '$path/typedef',
        "Template name '$typedef' shadows a primitive type");
  }

  _checkEnumAndBounds(node, path, out);
  _checkConstraintsForType(node, path, nodeType, declaredType, out);
  _checkEnv(node, path, out);
  _checkUi(node, path, out);
  _checkHelper(node, path, out);
  _checkHooks(node, path, out);
  _checkValidators(node, path, out);
  _checkComposite(node, path, nodeType, declaredType, templates, out);
  _checkPatterns(node, path, out);
  if (node.containsKey('default')) {
    _checkDefault(node, path, templates, out);
  }
}

/// The type a node behaves as: its own type, or the type of the
/// template its type names. `null` when the name resolves to nothing, in which
/// case type-applicability is not judged (the unknown name is reported
/// by [_checkTemplateReferences]). A template that resolves to a container
/// may be overridden like one (report A17).
String? _effectiveType(String declared, Map<String, Object?> templates) {
  var current = declared;
  for (var hops = 0; hops < 16; hops++) {
    if (DescriptorGrammar.primitiveTypes.contains(current)) return current;
    final template = templates[current];
    if (template is! Map<String, Object?>) return null;
    final next = template['type'];
    if (next is! String) return null;
    current = next;
  }
  return null;
}

void _checkEnumAndBounds(Map<String, Object?> node, String path, _IssueBuilder out) {
  final options = node['enum'];
  if (options is List<Object?>) {
    if (options.isEmpty) {
      out.add('INVALID_STRUCTURE', '$path/enum', 'enum must be nonempty');
    }
    final seen = <String>{};
    for (final option in options) {
      if (!seen.add(_valueKey(option))) {
        out.add('INVALID_STRUCTURE', '$path/enum', 'enum values must be unique');
        break;
      }
    }
  }
  for (final key in ['min_length', 'max_length', 'min_items', 'max_items']) {
    final value = node[key];
    if (_isExactInteger(value) && _compareNumbers(value, _numberZero) < 0) {
      out.add('INVALID_STRUCTURE', '$path/$key', '$key must not be negative');
    }
  }
  for (final pair in const [
    ['min_length', 'max_length'],
    ['min_items', 'max_items'],
    ['minimum', 'maximum'],
  ]) {
    final low = node[pair[0]], high = node[pair[1]];
    if (_isNumberValue(low) && _isNumberValue(high) && _compareNumbers(low, high) > 0) {
      out.add('INVALID_STRUCTURE', '$path/${pair[1]}',
          '${pair[1]} must not be below ${pair[0]}');
    }
  }
}

void _checkConstraintsForType(
  Map<String, Object?> node,
  String path,
  String? nodeType,
  String declaredType,
  _IssueBuilder out,
) {
  if (nodeType == null) return; // unknown template: UNKNOWN_TYPE already says so
  for (final entry in DescriptorGrammar.constraintTypes.entries) {
    if (!node.containsKey(entry.key)) continue;
    if (entry.value.contains(nodeType)) continue;
    out.add('INVALID_STRUCTURE', '$path/${entry.key}',
        "${entry.key} does not apply to type '$declaredType'");
  }
}

void _checkEnv(Map<String, Object?> node, String path, _IssueBuilder out) {
  final env = node['env'];
  if (env is! Map<String, Object?>) return;
  for (final key in env.keys) {
    if (!DescriptorGrammar.envKeys.contains(key)) {
      out.warn(unknownPropertyCode, '$path/env/$key', unknownPropertyMessage);
    }
  }
  if (env['allowed'] is! bool) {
    out.add('INVALID_STRUCTURE', '$path/env/allowed',
        'env.allowed is required and must be a boolean');
  }
  final convert = env['convert'];
  if (convert != null && !DescriptorGrammar.convertValues.contains(convert)) {
    out.add('INVALID_STRUCTURE', '$path/env/convert',
        'convert must be one of ${DescriptorGrammar.convertValues.join(', ')}');
  }
}

void _checkUi(Map<String, Object?> node, String path, _IssueBuilder out) {
  final ui = node['ui'];
  if (ui is! Map<String, Object?>) return;
  ui.forEach((key, value) {
    final childPath = '$path/ui/$key';
    if (!DescriptorGrammar.uiKeys.contains(key)) {
      out.warn(unknownPropertyCode, childPath, unknownPropertyMessage);
    } else if (key == 'rows') {
      if (!_isNumberValue(value) || _compareNumbers(value, _numberOne) < 0) {
        out.add('INVALID_STRUCTURE', childPath, 'ui.rows must be a positive integer');
      }
    } else if (const {'label', 'group', 'widget', 'placeholder', 'help'}.contains(key)) {
      if (value is! String) {
        out.add('INVALID_STRUCTURE', childPath, 'ui.$key must be a string');
      }
    }
  });
}

void _checkHelper(Map<String, Object?> node, String path, _IssueBuilder out) {
  final helper = node['helper'];
  if (helper is! Map<String, Object?>) return;
  for (final key in helper.keys) {
    if (!DescriptorGrammar.helperKeys.contains(key)) {
      out.warn(unknownPropertyCode, '$path/helper/$key', unknownPropertyMessage);
    }
  }
  final tag = helper['tag'];
  if (tag is! String || tag.isEmpty) {
    out.add('INVALID_STRUCTURE', '$path/helper/tag', 'helper.tag is required');
  }
  final actions = helper['actions'];
  if (actions is! List<Object?> || actions.isEmpty) {
    out.add('INVALID_STRUCTURE', '$path/helper/actions',
        'helper.actions must be a nonempty array');
  } else if (actions.any((a) => !DescriptorGrammar.helperActions.contains(a))) {
    out.add('INVALID_STRUCTURE', '$path/helper/actions',
        'helper.actions must be a subset of ${DescriptorGrammar.helperActions.join(', ')}');
  }
  final presentation = helper['presentation'];
  if (presentation != null &&
      !DescriptorGrammar.helperPresentations.contains(presentation)) {
    out.add('INVALID_STRUCTURE', '$path/helper/presentation',
        'helper.presentation must be one of ${DescriptorGrammar.helperPresentations.join(', ')}');
  }
}

void _checkHooks(Map<String, Object?> node, String path, _IssueBuilder out) {
  final hooks = node['hooks'];
  if (hooks is! Map<String, Object?>) return;
  hooks.forEach((event, bindings) {
    final eventPath = '$path/hooks/$event';
    if (!DescriptorGrammar.hookEvents.contains(event)) {
      out.add('INVALID_HOOK_EVENT', eventPath,
          'Unknown hook event; supported: ${DescriptorGrammar.hookEvents.join(', ')}');
      return;
    }
    if (bindings is! List<Object?> || bindings.isEmpty) {
      out.add('INVALID_STRUCTURE', eventPath, 'hook bindings must be a nonempty array');
      return;
    }
    for (var index = 0; index < bindings.length; index++) {
      final binding = bindings[index];
      final bindingPath = '$eventPath/$index';
      if (binding is! Map<String, Object?>) {
        out.add('INVALID_STRUCTURE', bindingPath, 'Binding must be an object');
        continue;
      }
      binding.forEach((key, value) {
        if (!DescriptorGrammar.bindingKeys.contains(key)) {
          out.warn(unknownPropertyCode, '$bindingPath/$key', unknownPropertyMessage);
        } else if (key == 'scope' && !DescriptorGrammar.hookScopes.contains(value)) {
          out.add('INVALID_STRUCTURE', '$bindingPath/$key',
              'scope must be one of ${DescriptorGrammar.hookScopes.join(', ')}');
        } else if (key == 'tag' && (value is! String || value.isEmpty)) {
          out.add('INVALID_STRUCTURE', '$bindingPath/$key', 'tag is required');
        }
      });
    }
  });
}

void _checkValidators(Map<String, Object?> node, String path, _IssueBuilder out) {
  final validators = node['validators'];
  if (validators is! List<Object?>) return;
  for (var index = 0; index < validators.length; index++) {
    final validator = validators[index];
    if (validator is! String || validator.isEmpty) {
      out.add('INVALID_STRUCTURE', '$path/validators/$index',
          'validator ids must be nonempty strings');
    }
  }
}

void _checkComposite(
  Map<String, Object?> node,
  String path,
  String? nodeType,
  String declaredType,
  Map<String, Object?> templates,
  _IssueBuilder out,
) {
  final children = node['children'];
  final additional = node['additional_children'];
  final options = node['children_options'];

  switch (nodeType) {
    case 'object':
      if (children is Map<String, Object?>) {
        children.forEach((label, child) {
          final childPath = '$path/children/$label';
          if (child is! Map<String, Object?>) {
            out.add('DESCRIPTOR_STRUCTURE', childPath, 'Child must be an object node');
            return;
          }
          _checkNode(child, childPath, out, allowId: true, templates: templates);
        });
      } else if (node.containsKey('children')) {
        out.add('DESCRIPTOR_STRUCTURE', '$path/children',
            'children of an object must map labels to nodes');
      }
      if (additional is Map<String, Object?>) {
        _checkNode(additional, '$path/additional_children', out,
            allowId: false, templates: templates);
      } else if (node.containsKey('additional_children')) {
        out.add('DESCRIPTOR_STRUCTURE', '$path/additional_children',
            'additional_children must be an object node');
      }
      if (node.containsKey('key_pattern') && node.containsKey('key_enum')) {
        out.add('INVALID_STRUCTURE', path,
            'key_pattern and key_enum are mutually exclusive');
      }
      if (node.containsKey('key_enum') && additional is! Map<String, Object?>) {
        out.add('INVALID_STRUCTURE', '$path/key_enum',
            'key_enum requires additional_children');
      }
      _checkUniqueFieldNames(node, path, out);
    case 'array':
      if (children is Map<String, Object?>) {
        if (_isItemNode(children)) {
          _checkNode(children, '$path/children', out,
              allowId: false, templates: templates);
        } else {
          out.add('DESCRIPTOR_STRUCTURE', '$path/children',
              'array children must be a single node describing every item');
        }
      }
      final hasOptions = options is List<Object?>;
      if (hasOptions && children is Map<String, Object?>) {
        out.add('INVALID_STRUCTURE', path,
            'children and children_options are mutually exclusive on arrays');
      } else if (!node.containsKey('children') && !hasOptions) {
        out.add('INVALID_STRUCTURE', path,
            'an array requires exactly one of children or children_options');
      } else if (node.containsKey('children') && hasOptions) {
        out.add('INVALID_STRUCTURE', path,
            'children and children_options are mutually exclusive on arrays');
      }
      if (hasOptions) {
        _checkOptionNodes(options, '$path/children_options', templates, out);
      }
    case 'union':
      if (options is List<Object?>) {
        _checkOptionNodes(options, '$path/children_options', templates, out);
      } else {
        out.add('INVALID_STRUCTURE', '$path/children_options', 'a union requires children_options');
      }
      if (children is Map<String, Object?> || children is String) {
        out.add('INVALID_STRUCTURE', '$path/children',
            'a union describes alternatives only through children_options');
      }
      if (additional is Map<String, Object?>) {
        out.add('INVALID_STRUCTURE', '$path/additional_children',
            'additional_children is not valid on a union');
      }
    default:
      for (final key in DescriptorGrammar.compositeKeys) {
        if (node.containsKey(key)) {
          out.add('INVALID_STRUCTURE', '$path/$key',
              '$key is not valid on type \'$declaredType\'');
        }
      }
      if (node.containsKey('key_pattern') || node.containsKey('key_enum')) {
        out.add('INVALID_STRUCTURE', path, 'key constraints are not valid on a scalar type');
      }
  }
}

void _checkOptionNodes(
  List<Object?> options,
  String optionsPath,
  Map<String, Object?> templates,
  _IssueBuilder out,
) {
  if (options.isEmpty) {
    out.add('INVALID_STRUCTURE', optionsPath, 'children_options must be a nonempty array');
  }
  for (var index = 0; index < options.length; index++) {
    final option = options[index];
    if (option is Map<String, Object?>) {
      _checkNode(option, '$optionsPath/$index', out,
          allowId: false, templates: templates);
    } else {
      out.add('DESCRIPTOR_STRUCTURE', '$optionsPath/$index', 'Node must be an object');
    }
  }
}

void _checkUniqueFieldNames(Map<String, Object?> node, String path, _IssueBuilder out) {
  final children = node['children'];
  if (children is! Map<String, Object?>) return;
  final seen = <String, String>{};
  children.forEach((label, child) {
    if (child is! Map<String, Object?>) return;
    final id = child['id'];
    final fieldName = id is String ? id : label;
    final previous = seen[fieldName];
    if (previous != null) {
      out.add('DUPLICATE_FIELD', '$path/children/$label',
          "Field name '$fieldName' is declared twice (also by '$previous')");
    }
    seen[fieldName] = label;
  });
}

void _checkPatterns(Map<String, Object?> node, String path, _IssueBuilder out) {
  // Both pattern fields are compile-checked. The baseline checks only
  // `pattern`, so a malformed key_pattern survives and then silently matches
  // nothing (report A15).
  for (final key in ['pattern', 'key_pattern']) {
    final value = node[key];
    if (value is! String) continue;
    try {
      RegExp(value);
    } on FormatException catch (e) {
      out.add('INVALID_PATTERN', '$path/$key', 'Unsupported pattern: ${e.message}');
    }
  }
}

void _checkDefault(
  Map<String, Object?> node,
  String path,
  Map<String, Object?> templates,
  _IssueBuilder out,
) {
  Map<String, Object?> resolved;
  try {
    resolved = _expandTemplates(node, templates, path) as Map<String, Object?>;
  } on DescriptorException catch (e) {
    out.add('INVALID_STRUCTURE', '$path/default', e.message);
    return;
  }
  late final DescriptorNode compiled;
  try {
    compiled = _buildNode(resolved, path, templates: templates);
  } on DescriptorException catch (e) {
    out.add('INVALID_STRUCTURE', '$path/default', e.message);
    return;
  }
  if (!_defaultSatisfies(node['default'], compiled)) {
    out.add('INVALID_DEFAULT', '$path/default',
        'default does not satisfy the node constraints');
  }
}

// -- templates -------------------------------------------------------------

void _collectTemplates(Object? data, Map<String, Object?> into) {
  void walk(Object? node) {
    if (node is! Map<String, Object?>) return;
    final name = node['typedef'];
    if (name is String) into.putIfAbsent(name, () => node);
    for (final child in _structuralChildren(node)) {
      walk(child);
    }
  }

  walk(_descriptorRootNode(data));
}

void _checkTemplateDuplicates(Object? data, _IssueBuilder out) {
  final seen = <String>{};
  void walk(Map<String, Object?> node, String nodePath) {
    final name = node['typedef'];
    if (name is String) {
      if (!seen.add(name)) {
        out.add('DUPLICATE_TYPEDEF', '$nodePath/typedef',
            "Template name '$name' is declared more than once");
      }
    }
    for (final (child, childPath) in _structuralChildNodes(node, nodePath)) {
      walk(child, childPath);
    }
  }

  final root = _descriptorRootNode(data);
  if (root is Map<String, Object?>) walk(root, '/root');
}

void _checkTemplateReferences(
    Object? data, Map<String, Object?> templates, _IssueBuilder out) {
  void walk(Map<String, Object?> node, String nodePath, List<String> seen) {
    final nodeType = node['type'];
    if (nodeType is String && !DescriptorGrammar.primitiveTypes.contains(nodeType)) {
      if (!templates.containsKey(nodeType)) {
        out.add('UNKNOWN_TYPE', '$nodePath/type', "Unknown type or template '$nodeType'");
      } else if (seen.contains(nodeType)) {
        out.add('TEMPLATE_CYCLE', '$nodePath/type',
            'Cyclic template reference: ${[...seen, nodeType].join(' -> ')}');
      } else {
        final template = templates[nodeType];
        if (template is Map<String, Object?>) {
          walk(template, '$nodePath<$nodeType>', [...seen, nodeType]);
        }
      }
    }
    for (final (child, childPath) in _structuralChildNodes(node, nodePath)) {
      walk(child, childPath, seen);
    }
  }

  final root = _descriptorRootNode(data);
  if (root is Map<String, Object?>) walk(root, '/root', const []);
}

Object? _descriptorRootNode(Object? data) =>
    data is Map<String, Object?> && data['root'] is Map<String, Object?>
        ? data['root']
        : data;

List<Map<String, Object?>> _structuralChildren(Map<String, Object?> node) =>
    [for (final (child, _) in _structuralChildNodes(node, '')) child];

/// The node definitions nested inside [node], with the descriptor path
/// each one is written at.
List<(Map<String, Object?>, String)> _structuralChildNodes(
    Map<String, Object?> node, String path) {
  final out = <(Map<String, Object?>, String)>[];
  final children = node['children'];
  if (children is Map<String, Object?>) {
    if (_isItemNode(children)) {
      out.add((children, '$path/children'));
    } else {
      children.forEach((label, child) {
        if (child is Map<String, Object?>) out.add((child, '$path/children/$label'));
      });
    }
  }
  final additional = node['additional_children'];
  if (additional is Map<String, Object?>) out.add((additional, '$path/additional_children'));
  final options = node['children_options'];
  if (options is List<Object?>) {
    for (var index = 0; index < options.length; index++) {
      final option = options[index];
      if (option is Map<String, Object?>) {
        out.add((option, '$path/children_options/$index'));
      }
    }
  }
  return out;
}

/// An array item node is a node object; an object children map is labelled.
bool _isItemNode(Map<String, Object?> children) => children['type'] is String;

// -- positions -------------------------------------------------------------------

/// Attaches the source position of every issue that carries only a path.
///
/// The descriptor is a JSON5 document and an issue path is a JSON Pointer into
/// it, so the position comes from the same tree the editor uses. A path naming
/// a property that is not there is reported at the nearest existing ancestor,
/// which is where the author has to look. Columns count Unicode code points,
/// like every other length in this product.
List<DescriptorIssue> _locateIssues(
    Json5Document document, List<DescriptorIssue> issues) {
  return [
    for (final issue in issues) _locateOne(document, issue),
  ];
}

DescriptorIssue _locateOne(Json5Document document, DescriptorIssue issue) {
  var pointer = issue.path;
  while (true) {
    final node = _findQuietly(document, pointer);
    if (node != null) {
      final (line, column) = _codePointPosition(document, node.span.startUnit);
      return issue.withPosition(line, column);
    }
    if (pointer.isEmpty) return issue;
    final cut = pointer.lastIndexOf('/');
    pointer = cut <= 0 ? '' : pointer.substring(0, cut);
  }
}

ValueNode? _findQuietly(Json5Document document, String pointer) {
  try {
    return document.find(pointer);
  } on Json5SourceException {
    return null;
  }
}

/// The 1-based (line, column) of a code-unit offset, with the column counted in
/// Unicode code points.
(int, int) _codePointPosition(Json5Document document, int unitOffset) {
  final text = document.text;
  final clamped = unitOffset > text.length ? text.length : unitOffset;
  final line = '\n'.allMatches(text.substring(0, clamped)).length + 1;
  final lastNewline = clamped == 0 ? -1 : text.lastIndexOf('\n', clamped - 1);
  final column = codePointLength(text.substring(lastNewline + 1, clamped)) + 1;
  return (line, column);
}

/// The number of Unicode code points in [text]; a surrogate pair counts once.
int codePointLength(String text) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) i++;
    }
    count++;
  }
  return count;
}

// -- value helpers used by the default check ------------------------------------

const Object _numberZero = 0;
const Object _numberOne = 1;

bool _isNumberValue(Object? value) =>
    value is int || value is BigInt || value is double;

/// Compares two numeric values exactly, without losing a `BigInt`
/// through a `double`.
int _compareNumbers(Object? a, Object? b) {
  if (a is BigInt || b is BigInt) {
    return _toBigInt(a).compareTo(_toBigInt(b));
  }
  return _toDouble(a).compareTo(_toDouble(b));
}

BigInt _toBigInt(Object? value) => switch (value) {
      final int v => BigInt.from(v),
      final BigInt v => v,
      final double v => _bigIntFromDouble(v),
      _ => BigInt.zero,
    };

BigInt _bigIntFromDouble(double value) {
  if (!value.isFinite) {
    return value.isNaN
        ? BigInt.zero
        : (value > 0 ? DescriptorGrammar.maxExactInt : -DescriptorGrammar.maxExactInt);
  }
  return BigInt.from(value.truncateToDouble());
}

double _toDouble(Object? value) => switch (value) {
      final int v => v.toDouble(),
      final BigInt v => v.toDouble(),
      final double v => v,
      _ => double.nan,
    };

/// A canonical key distinguishing values the baseline's `repr`
/// distinguishes: `1`, `1.0` and `true` are three different enum members.
String _valueKey(Object? value) => switch (value) {
      null => 'null',
      final bool v => 'bool:$v',
      final int v => 'int:$v',
      final BigInt v => 'int:$v',
      final double v => 'double:$v',
      final String v => "'$v'",
      final TemplateRef v => 'template:${v.name}:${v.defaultText}',
      final List<Object?> v => '[${v.map(_valueKey).join(',')}]',
      final Map<String, Object?> v =>
        '{${(v.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => "'${e.key}':${_valueKey(e.value)}")
            .join(',')}}',
      final Object v => 'other:$v',
    };

/// Deep equality without implicit conversion, as the baseline compares
/// `const` and `enum` members.
bool _sameValue(Object? expected, Object? actual) {
  if (expected is bool || actual is bool) {
    return expected is bool && actual is bool && expected == actual;
  }
  if (expected == null || actual == null) return expected == null && actual == null;
  if (_isNumberValue(expected) && _isNumberValue(actual)) {
    return _compareNumbers(expected, actual) == 0;
  }
  if (expected is String && actual is String) return expected == actual;
  if (expected is List<Object?> && actual is List<Object?>) {
    return expected.length == actual.length &&
        List.generate(expected.length, (i) => i)
            .every((i) => _sameValue(expected[i], actual[i]));
  }
  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    if (expected.length != actual.length) return false;
    return expected.keys.every((key) =>
        actual.containsKey(key) && _sameValue(expected[key], actual[key]));
  }
  return false;
}

extension on DescriptorIssue {
  DescriptorIssue copyWithSeverity(DescriptorSeverity severity) => DescriptorIssue(
        code: code,
        severity: severity,
        path: path,
        message: message,
        line: line,
        column: column,
      );
}
