part of 'descriptor.dart';

/// A descriptor fragment: a document mounted at a position of the
/// base descriptor (`SPEC.md` amendment 7).
final class DescriptorFragment {
  /// Creates a fragment with its [source] and the descriptor [mount] pointer.
  const DescriptorFragment({required this.source, required this.mount});

  /// The fragment document text.
  final String source;

  /// Where it mounts, e.g. `/root/children/extra`.
  final String mount;
}

/// A compiled descriptor node: one declaration with its
/// type, constraints, defaults, key governance, policy flags and nested nodes,
/// all resolved.
///
/// Instances are immutable and built by [compileDescriptor]. [secret],
/// [readOnly] and [apply] carry the value inherited from the nearest ancestor
/// that declared one, which is what the write pipeline and the
/// editor read.
final class DescriptorNode {
  /// Builds a compiled node.
  DescriptorNode._({
    required this.type,
    required this.path,
    this.label,
    this.fieldName,
    required this.typedefName,
    required this.description,
    required this.title,
    required this.required,
    required this.nullable,
    required this.hasDefault,
    required this.defaultValue,
    required this.enumValues,
    required this.hasConst,
    required this.constValue,
    required this.minimum,
    required this.maximum,
    required this.minLength,
    required this.maxLength,
    required this.pattern,
    required this.minItems,
    required this.maxItems,
    required this.uniqueItems,
    required this.keyPattern,
    required this.keyEnum,
    required this.envAllowed,
    required this.envConvert,
    required this.secret,
    required this.readOnly,
    required this.apply,
    required this.validators,
    required this.ui,
    required this.helper,
    required this.hooks,
    required this.children,
    required this.additionalChildren,
    required this.itemNode,
    required this.optionNodes,
    this.parent,
  });

  /// The pointer of this node's child by field name.
  String childPointer(String childFieldName) =>
      '${path == '/root' ? '' : path}/${escapePointerToken(childFieldName)}';

  /// The declared type: one of [DescriptorGrammar.primitiveTypes] after
  /// template resolution.
  final String type;

  /// Pointer of this node inside the descriptor document.
  final String path;

  /// The label this node was written under, when it is a child.
  final String? label;

  /// The field name the node governs: [label] unless `id` renamed it.
  final String? fieldName;

  /// The template this node declares, if any.
  final String? typedefName;

  /// The user-facing description, in either form of `SPEC_.md` 41.
  final DescriptorText? description;

  /// The user-facing title, in either form of `SPEC_.md` 41.
  final DescriptorText? title;

  /// Whether a value must be present.
  final bool required;

  /// Whether an explicit null is allowed.
  final bool nullable;

  /// Whether the descriptor declared a default at all — distinct
  /// from a default whose value happens to be null.
  final bool hasDefault;

  /// The declared default value.
  final Object? defaultValue;

  /// The allowed values, or `null` when the node declares no enum.
  final List<Object?>? enumValues;

  /// Whether a `const` was declared.
  final bool hasConst;

  /// The fixed value.
  final Object? constValue;

  /// Numeric bounds for `int` and `number` nodes.
  final Object? minimum, maximum;

  /// Length bounds for `string` nodes.
  final Object? minLength, maxLength;

  /// The accepted pattern for `string` nodes, in the dialect of
  /// `docs/grammars.md` §1.
  final String? pattern;

  /// Item count bounds for `array` nodes.
  final Object? minItems, maxItems;

  /// Whether array items must be distinct.
  final bool? uniqueItems;

  /// The pattern governing dynamic keys.
  final String? keyPattern;

  /// The closed set of governed keys.
  final List<String>? keyEnum;

  /// Whether `${VAR}` substitution is allowed here.
  final bool envAllowed;

  /// The conversion applied to a resolved environment value.
  final String? envConvert;

  /// Whether the value is a secret (inherited).
  final bool secret;

  /// Whether the node is read-only (inherited).
  final bool readOnly;

  /// The application policy (inherited): `live`, `reload` or
  /// `restart`.
  final String apply;

  /// Names of the semantic validators to run.
  final List<String> validators;

  /// Presentation hints, carried uninterpreted.
  final Map<String, Object?>? ui;

  /// The helper capability binding.
  final Map<String, Object?>? helper;

  /// The lifecycle hook bindings.
  final Map<String, Object?>? hooks;

  /// Declared children keyed by field name, in declaration order.
  final Map<String, DescriptorNode>? children;

  /// The node governing keys that are not declared.
  final DescriptorNode? additionalChildren;

  /// The single node describing every item of an array.
  final DescriptorNode? itemNode;

  /// The alternatives of a union, or the per-index nodes of an array.
  final List<DescriptorNode>? optionNodes;

  /// The node this one was built under, for inheritance.
  final DescriptorNode? parent;

  /// The child governing [fieldName], or `null`.
  DescriptorNode? child(String fieldName) => children?[fieldName];

  /// Whether this type holds no nested nodes.
  bool get isScalar => type != 'object' && type != 'array' && type != 'union';

  @override
  String toString() => 'DescriptorNode($type at $path)';
}

/// A compiled descriptor: the root node, the revision of its source and the
/// envelope values that identify it.
final class CompiledDescriptor {
  /// Created by [compileDescriptor].
  CompiledDescriptor({
    required this.root,
    required this.source,
    required this.revision,
    required this.project,
    required this.configVersion,
    required this.defaultLanguage,
    required this.flutterExtension,
  });

  /// The compiled root node.
  final DescriptorNode root;

  /// The descriptor source text it was compiled from.
  final String source;

  /// The revision of [source] (`SPEC.md` amendment 8).
  final String revision;

  /// The declared project, or `null`.
  final String? project;

  /// The declared configuration version, or `null`.
  final String? configVersion;

  /// The language a localized description falls back to when it declares none.
  final String defaultLanguage;

  /// The `x_aiset_flutter` envelope entry, preserved uninterpreted. The
  /// Flutter layer reads it; the core never executes metadata
  /// (`SPEC.md` amendment 5).
  final Map<String, Object?>? flutterExtension;

  /// The compiled node addressed by the JSON Pointer [pointer], or `null` when
  /// the descriptor declares nothing there.
  ///
  /// A key of an object typed as a union resolves through the alternatives in
  /// declaration order; an undeclared key resolves through
  /// `additional_children` when the key constraints admit it; an array
  /// index resolves through the item node, clamped to the last
  /// alternative of a `children_options` array.
  DescriptorNode? nodeAt(String pointer) {
    DescriptorNode? node = root;
    for (final token in parsePointer(pointer)) {
      final current = node;
      if (current == null) return null;
      if (current.type == 'object') {
        node = current.children?[token] ??
            _unionChild(current, token) ??
            _dynamicChild(current, token);
      } else if (current.type == 'array') {
        node = _arrayItemNode(current, token);
      } else if (current.type == 'union') {
        node = _unionChild(current, token);
      } else {
        return null;
      }
    }
    return node;
  }

  /// Whether [pointer] addresses a declared node.
  bool hasNode(String pointer) => nodeAt(pointer) != null;
}

DescriptorNode? _unionChild(DescriptorNode node, String token) {
  for (final option in node.optionNodes ?? const <DescriptorNode>[]) {
    if (option.type == 'object') {
      final child = option.children?[token];
      if (child != null) return child;
    }
  }
  return null;
}

DescriptorNode? _dynamicChild(DescriptorNode node, String token) {
  final additional = node.additionalChildren;
  if (additional == null) return null;
  final allowedKeys = node.keyEnum;
  if (allowedKeys != null && allowedKeys.isNotEmpty && !allowedKeys.contains(token)) {
    return null;
  }
  final pattern = node.keyPattern;
  if (pattern != null && pattern.isNotEmpty && !_prefixMatch(pattern, token)) return null;
  return additional;
}

DescriptorNode? _arrayItemNode(DescriptorNode node, String token) {
  if (!_isPlainIndex(token)) return null;
  final options = node.optionNodes;
  if (options != null) {
    if (options.isEmpty) return null;
    final index = int.parse(token);
    return options[index < options.length ? index : options.length - 1];
  }
  return node.itemNode;
}

bool _isPlainIndex(String token) {
  if (token.isEmpty) return false;
  for (final unit in token.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return token == '0' || !token.startsWith('0');
}

bool _prefixMatch(String pattern, String subject) =>
    RegExp(pattern).matchAsPrefix(subject) != null;

// -- compilation ----------------------------------------------------------

/// Validates and compiles descriptor [source] into an immutable tree.
///
/// [typedefSources] are descriptor documents whose `typedef` declarations are
/// available to this one; [fragments] are mounted into the tree before it is
/// compiled; [strict] refuses unknown metadata instead of warning about it.
/// [defaultLanguage] is the language a localized `description` or `title` falls
/// back to when the wrapper declares no `default` (`SPEC_.md` amendment 41).
///
/// Throws [DescriptorException] with the stable code `INVALID_DESCRIPTOR` when
/// the grammar refuses the document, and lets [Json5ParseException] through
/// (`PARSE_ERROR`) when the source is not readable JSON5.
CompiledDescriptor compileDescriptor(
  String source, {
  List<String> typedefSources = const [],
  List<DescriptorFragment> fragments = const [],
  bool strict = false,
  String defaultLanguage = defaultDescriptorLanguage,
}) {
  final data = _readDescriptorDocument(source, '<descriptor>');
  final templates = <String, Object?>{};
  _collectTemplates(data, templates);
  for (final extra in typedefSources) {
    _mergeDeclaredTemplates(
        _readDescriptorDocument(extra, '<typedef source>'), templates);
  }
  for (final fragment in fragments) {
    _mergeDeclaredTemplates(
        _readDescriptorDocument(fragment.source, '<fragment>'), templates);
  }

  final diagnostic =
      validateDescriptor(source, strict: strict, knownTemplates: templates);
  final errors = diagnostic.errors;
  if (errors.isNotEmpty) {
    throw DescriptorException('Descriptor is invalid', issues: errors);
  }

  final expanded = _expandTemplates(data[DescriptorGrammar.rootKey], templates, '/root');
  var composed = <String, Object?>{...data, DescriptorGrammar.rootKey: expanded};
  if (fragments.isNotEmpty) {
    composed = _composeFragments(composed, fragments);
    // The composed tree is validated as data. The baseline re-serializes it to
    // JSON and re-parses that, so a composition failure is
    // reported at a position inside a generated dump rather than in either
    // file the author wrote (report A20).
    final afterComposition = _diagnose(composed, null,
        strict: strict, knownTemplates: templates);
    final compositionErrors = afterComposition.errors;
    if (compositionErrors.isNotEmpty) {
      throw DescriptorException('Composed descriptor is invalid',
          issues: compositionErrors);
    }
  }

  final root = _buildNode(composed[DescriptorGrammar.rootKey], '/root',
      templates: templates, defaultLanguage: defaultLanguage);
  return CompiledDescriptor(
    root: root,
    source: source,
    revision: descriptorRevision(source),
    project: data['project'] is String ? data['project'] as String : null,
    configVersion: data['config_version'] is String
        ? data['config_version'] as String
        : null,
    defaultLanguage: defaultLanguage,
    flutterExtension: data['x_aiset_flutter'] is Map<String, Object?>
        ? data['x_aiset_flutter'] as Map<String, Object?>
        : null,
  );
}

Map<String, Object?> _readDescriptorDocument(String source, String origin) {
  final document = Json5Document(source, origin: origin);
  final data = document.storedValue();
  if (data is! Map<String, Object?>) {
    throw DescriptorException('Descriptor root must be an object');
  }
  return data;
}

void _mergeDeclaredTemplates(Map<String, Object?> data, Map<String, Object?> into) {
  final declared = <String, Object?>{};
  _collectTemplates(data, declared);
  declared.forEach((name, node) {
    if (into.containsKey(name)) {
      throw DescriptorException("Template name '$name' is declared more than once",
          path: '/root');
    }
    into[name] = node;
  });
}

// -- template expansion ---------------------------------------------------------

Object? _expandTemplates(Object? data, Map<String, Object?> templates, String path) {
  if (data is Map<String, Object?> &&
      data[DescriptorGrammar.rootKey] is Map<String, Object?>) {
    return <String, Object?>{
      ...data,
      DescriptorGrammar.rootKey:
          _expandTemplates(data[DescriptorGrammar.rootKey], templates, '$path/root'),
    };
  }
  if (data is! Map<String, Object?>) return data;

  final node = <String, Object?>{...data}..remove('typedef');
  final nodeType = node['type'];
  if (nodeType is String && !DescriptorGrammar.primitiveTypes.contains(nodeType)) {
    final template = templates[nodeType];
    if (template is! Map<String, Object?>) {
      throw DescriptorException("Unknown type or template '$nodeType'", path: path);
    }
    final base = <String, Object?>{...template}..remove('typedef');
    node.addAll(_mergeTemplate(
        _expandTemplates(base, templates, path) as Map<String, Object?>, node));
  }
  final children = node['children'];
  if (children is Map<String, Object?>) {
    if (node['type'] == 'array' && _isItemNode(children)) {
      node['children'] = _expandTemplates(children, templates, '$path/children');
    } else {
      node['children'] = <String, Object?>{
        for (final entry in children.entries)
          entry.key: _expandTemplates(entry.value, templates, '$path/children/${entry.key}'),
      };
    }
  }
  if (node['additional_children'] is Map<String, Object?>) {
    node['additional_children'] =
        _expandTemplates(node['additional_children'], templates, '$path/additional_children');
  }
  final options = node['children_options'];
  if (options is List<Object?>) {
    node['children_options'] = [
      for (var index = 0; index < options.length; index++)
        _expandTemplates(options[index], templates, '$path/children_options/$index'),
    ];
  }
  return node;
}

/// Merges a template definition with the node that references it.
///
/// Object children merge by label and `children_options` merge by index;
/// every other property is replaced by the referencing node. A node position
/// that holds a node rather than a label map — the single item node of
/// an array — merges as a node too (the baseline passes the two type
/// strings into a dictionary merge and raises `ValueError`, report A18).
Map<String, Object?> _mergeTemplate(
    Map<String, Object?> base, Map<String, Object?> override) {
  final merged = <String, Object?>{...base};
  for (final entry in override.entries) {
    final key = entry.key;
    if (key == 'type') continue; // the reference names the template, not the type
    final value = entry.value;
    final existing = base[key];
    if ((key == 'children' || key == 'children_options') &&
        value is Object &&
        _sameShape(existing, value)) {
      if (existing is Map<String, Object?> && value is Map<String, Object?>) {
        merged[key] = _isNodeObject(existing) && _isNodeObject(value)
            ? _mergeTemplate(existing, value)
            : <String, Object?>{
                ...existing,
                for (final childEntry in value.entries)
                  childEntry.key: existing.containsKey(childEntry.key)
                      ? _mergeTemplate(
                          existing[childEntry.key] as Map<String, Object?>,
                          childEntry.value as Map<String, Object?>)
                      : childEntry.value,
              };
      } else if (existing is List<Object?> && value is List<Object?>) {
        final combined = [...existing];
        for (var index = 0; index < value.length; index++) {
          if (index < combined.length &&
              combined[index] is Map<String, Object?> &&
              value[index] is Map<String, Object?>) {
            combined[index] = _mergeTemplate(combined[index] as Map<String, Object?>,
                value[index] as Map<String, Object?>);
          } else {
            combined.add(value[index]);
          }
        }
        merged[key] = combined;
      } else {
        merged[key] = value;
      }
    } else {
      merged[key] = value;
    }
  }
  return merged;
}

bool _sameShape(Object? a, Object? b) =>
    (a is Map && b is Map) || (a is List && b is List);

bool _isNodeObject(Map<String, Object?> value) => value['type'] is String;

// -- fragment composition -------------------------------------------------------

Map<String, Object?> _composeFragments(
    Map<String, Object?> data, List<DescriptorFragment> fragments) {
  var composed = <String, Object?>{...data};
  for (final fragment in fragments) {
    final fragmentData = _readDescriptorDocument(fragment.source, '<fragment>');
    final root = fragmentData[DescriptorGrammar.rootKey];
    if (root is! Map<String, Object?>) {
      throw DescriptorException(
          'A descriptor fragment must contain a root object node',
          path: fragment.mount);
    }
    composed = _mount(composed, fragment.mount, root);
  }
  return composed;
}

/// Attaches [root] at [mount]. The path is walked through the nodes that
/// already exist, and only the final position has to be free
/// (`SPEC.md` amendment 7). The baseline refuses every mount deeper than one
/// level with a false collision (report A13).
Map<String, Object?> _mount(
    Map<String, Object?> data, String mount, Map<String, Object?> root) {
  final tokens = parsePointer(mount);
  if (tokens.isEmpty || tokens.first != DescriptorGrammar.rootKey) {
    throw DescriptorException(
        "Fragment mount must start with /${DescriptorGrammar.rootKey}, got '$mount'",
        path: mount);
  }
  final base = data[DescriptorGrammar.rootKey]! as Map<String, Object?>;
  final rest = tokens.sublist(1);
  if (rest.isEmpty) {
    if (base.containsKey('children') || base.containsKey('additional_children')) {
      throw DescriptorException(
          'A fragment cannot replace a populated root node; mount it under a field name',
          path: mount);
    }
    return <String, Object?>{...data, DescriptorGrammar.rootKey: root};
  }
  return <String, Object?>{
    ...data,
    DescriptorGrammar.rootKey: _mountInto(base, rest, mount, root),
  };
}

/// Returns a copy of [node] with [root] attached at [tokens], which always
/// addresses a position inside this node. Nothing in the caller's document is
/// mutated.
Map<String, Object?> _mountInto(Map<String, Object?> node, List<String> tokens,
    String mount, Map<String, Object?> root) {
  final head = tokens.first;
  if (head != 'children') {
    if (node.containsKey(head)) {
      throw DescriptorException(
          "Fragment mount '$mount' collides with an existing descriptor node",
          path: mount);
    }
    return <String, Object?>{...node, head: root};
  }
  if (tokens.length < 2) {
    throw DescriptorException(
        "Fragment mount '$mount' must address a free field name", path: mount);
  }
  final children = node['children'];
  if (children is! Map<String, Object?>) {
    throw DescriptorException("Fragment mount '$mount' does not exist", path: mount);
  }
  final label = tokens[1];
  final isLast = tokens.length == 2;
  if (isLast) {
    if (children.containsKey(label)) {
      throw DescriptorException(
          "Fragment mount '$mount' collides with an existing descriptor node",
          path: mount);
    }
    return <String, Object?>{...node, 'children': {...children, label: root}};
  }
  final existing = children[label];
  if (existing is! Map<String, Object?>) {
    throw DescriptorException("Fragment mount '$mount' does not exist", path: mount);
  }
  return <String, Object?>{
    ...node,
    'children': {
      ...children,
      label: _mountInto(existing, tokens.sublist(2), mount, root),
    },
  };
}

// -- node building --------------------------------------------------------------

DescriptorNode _buildNode(
  Object? raw,
  String path, {
  DescriptorNode? parent,
  required Map<String, Object?> templates,
  String defaultLanguage = defaultDescriptorLanguage,
  String? label,
  String? fieldName,
}) {
  if (raw is! Map<String, Object?>) {
    throw DescriptorException('Node must be an object', path: path);
  }
  final nodeType = raw['type'];
  if (nodeType is! String) {
    throw DescriptorException('type is required', path: path);
  }
  final env = raw['env'] is Map<String, Object?>
      ? raw['env'] as Map<String, Object?>
      : const <String, Object?>{};

  Object? inherited(String name) {
    if (raw.containsKey(name)) return raw[name];
    if (parent == null) return null;
    switch (name) {
      case 'secret':
        return parent.secret;
      case 'read_only':
        return parent.readOnly;
      case 'apply':
        return parent.apply;
    }
    return null;
  }

  final declaredApply = raw['apply'];
  final applyPolicy = declaredApply is String && declaredApply.isNotEmpty
      ? declaredApply
      : (parent?.apply ?? 'restart');

  DescriptorText? text(String key) => readDescriptorText(
        raw[key],
        path: '$path/$key',
        report: (_, _, _) {},
        defaultLanguage: defaultLanguage,
      );

  // Nested nodes are built with this node as their parent, so the inheritance
  // of secret, read_only and apply is resolved during construction rather than
  // by a later pass.
  final pending = _pendingNode(raw, path, nodeType, env, inherited, applyPolicy, text,
      label: label, fieldName: fieldName, parent: parent);
  return _withNested(pending, raw, path, nodeType, templates, defaultLanguage);
}

DescriptorNode _pendingNode(
  Map<String, Object?> raw,
  String path,
  String nodeType,
  Map<String, Object?> env,
  Object? Function(String) inherited,
  String applyPolicy,
  DescriptorText? Function(String) text, {
  required String? label,
  required String? fieldName,
  required DescriptorNode? parent,
}) =>
    DescriptorNode._(
      type: nodeType,
      path: path,
      label: label,
      fieldName: fieldName,
      typedefName: raw['typedef'] is String ? raw['typedef'] as String : null,
      description: text('description'),
      title: text('title'),
      required: raw['required'] == true,
      nullable: raw['nullable'] == true,
      hasDefault: raw.containsKey('default'),
      defaultValue: raw['default'],
      enumValues:
          raw['enum'] is List<Object?> ? [...raw['enum']! as List<Object?>] : null,
      hasConst: raw.containsKey('const'),
      constValue: raw['const'],
      minimum: raw['minimum'],
      maximum: raw['maximum'],
      minLength: raw['min_length'],
      maxLength: raw['max_length'],
      pattern: raw['pattern'] is String ? raw['pattern'] as String : null,
      minItems: raw['min_items'],
      maxItems: raw['max_items'],
      uniqueItems: raw['unique_items'] is bool ? raw['unique_items'] as bool : null,
      keyPattern: raw['key_pattern'] is String ? raw['key_pattern'] as String : null,
      keyEnum: raw['key_enum'] is List<Object?>
          ? [for (final key in raw['key_enum']! as List<Object?>) '$key']
          : null,
      envAllowed: env['allowed'] == true,
      envConvert: env['convert'] is String ? env['convert'] as String : null,
      secret: inherited('secret') == true,
      readOnly: inherited('read_only') == true,
      apply: applyPolicy,
      validators: raw['validators'] is List<Object?>
          ? [for (final v in raw['validators']! as List<Object?>) '$v']
          : const [],
      ui: raw['ui'] is Map<String, Object?> ? {...raw['ui']! as Map<String, Object?>} : null,
      helper:
          raw['helper'] is Map<String, Object?> ? {...raw['helper']! as Map<String, Object?>} : null,
      hooks:
          raw['hooks'] is Map<String, Object?> ? {...raw['hooks']! as Map<String, Object?>} : null,
      children: null,
      additionalChildren: null,
      itemNode: null,
      optionNodes: null,
      parent: parent,
    );

DescriptorNode _withNested(
  DescriptorNode pending,
  Map<String, Object?> raw,
  String path,
  String nodeType,
  Map<String, Object?> templates,
  String defaultLanguage,
) {
  Map<String, DescriptorNode>? children;
  DescriptorNode? additional;
  DescriptorNode? item;
  List<DescriptorNode>? options;

  if (nodeType == 'object') {
    final rawChildren = raw['children'];
    if (rawChildren is Map<String, Object?>) {
      children = <String, DescriptorNode>{};
      rawChildren.forEach((childLabel, childRaw) {
        final childPath = '$path/children/$childLabel';
        if (childRaw is! Map<String, Object?>) {
          throw DescriptorException('Child must be an object node', path: childPath);
        }
        final id = childRaw['id'];
        final fieldName = id is String ? id : childLabel;
        if (children!.containsKey(fieldName)) {
          throw DescriptorException("Duplicate field name '$fieldName'", path: childPath);
        }
        children[fieldName] = _buildNode(childRaw, childPath,
            parent: pending,
            templates: templates,
            defaultLanguage: defaultLanguage,
            label: childLabel,
            fieldName: fieldName);
      });
      if (children.isEmpty) children = null;
    }
    final rawAdditional = raw['additional_children'];
    if (rawAdditional is Map<String, Object?>) {
      additional = _buildNode(rawAdditional, '$path/additional_children',
          parent: pending, templates: templates, defaultLanguage: defaultLanguage);
    }
  } else if (nodeType == 'array' || nodeType == 'union') {
    final rawChildren = raw['children'];
    if (rawChildren is Map<String, Object?> && _isItemNode(rawChildren)) {
      item = _buildNode(rawChildren, '$path/children',
          parent: pending, templates: templates, defaultLanguage: defaultLanguage);
    }
    final rawOptions = raw['children_options'];
    if (rawOptions is List<Object?>) {
      options = [
        for (var index = 0; index < rawOptions.length; index++)
          _buildNode(rawOptions[index], '$path/children_options/$index',
              parent: pending, templates: templates, defaultLanguage: defaultLanguage),
      ];
    }
  }

  return DescriptorNode._(
    type: pending.type,
    path: pending.path,
    label: pending.label,
    fieldName: pending.fieldName,
    typedefName: pending.typedefName,
    description: pending.description,
    title: pending.title,
    required: pending.required,
    nullable: pending.nullable,
    hasDefault: pending.hasDefault,
    defaultValue: pending.defaultValue,
    enumValues: pending.enumValues,
    hasConst: pending.hasConst,
    constValue: pending.constValue,
    minimum: pending.minimum,
    maximum: pending.maximum,
    minLength: pending.minLength,
    maxLength: pending.maxLength,
    pattern: pending.pattern,
    minItems: pending.minItems,
    maxItems: pending.maxItems,
    uniqueItems: pending.uniqueItems,
    keyPattern: pending.keyPattern,
    keyEnum: pending.keyEnum,
    envAllowed: pending.envAllowed,
    envConvert: pending.envConvert,
    secret: pending.secret,
    readOnly: pending.readOnly,
    apply: pending.apply,
    validators: pending.validators,
    ui: pending.ui,
    helper: pending.helper,
    hooks: pending.hooks,
    children: children,
    additionalChildren: additional,
    itemNode: item,
    optionNodes: options,
    parent: pending.parent,
  );
}

// -- default check --------------------------------------------------------------

/// Whether a declared default satisfies its node.
///
/// This is the compile-time subset of the validator: type, null rule, bounds,
/// lengths, pattern, enum, const, object children and required keys, array
/// item rules and union alternatives. The full validator of stage 2C
/// generalizes the same rules to configuration values.
bool _defaultSatisfies(Object? value, DescriptorNode node) {
  if (value is TemplateRef) return false; // a placeholder is not a value yet
  if (node.type == 'any') return true;
  if (value == null) return node.nullable || node.type == 'null';
  if (node.type == 'union') {
    final options = node.optionNodes ?? const <DescriptorNode>[];
    return options.any((option) => _defaultSatisfies(value, option));
  }
  if (!_typeMatches(node.type, value)) return false;

  switch (node.type) {
    case 'int':
      if (!_withinExactRange(value)) return false;
      break;
    case 'object':
      final map = value as Map<String, Object?>;
      for (final entry in map.entries) {
        final child = node.children?[entry.key] ??
            _dynamicChild(node, entry.key);
        if (child == null || !_defaultSatisfies(entry.value, child)) return false;
      }
      for (final child in node.children?.values ?? const <DescriptorNode>[]) {
        if (child.required && !map.containsKey(child.fieldName)) return false;
      }
      break;
    case 'array':
      final items = value as List<Object?>;
      if (node.minItems != null &&
          _compareNumbers(items.length, node.minItems) < 0) {
        return false;
      }
      if (node.maxItems != null &&
          _compareNumbers(items.length, node.maxItems) > 0) {
        return false;
      }
      if (node.uniqueItems == true) {
        final keys = items.map(_valueKey).toList();
        if (keys.toSet().length != keys.length) return false;
      }
      final options = node.optionNodes;
      for (var index = 0; index < items.length; index++) {
        if (options != null) {
          if (!options.any((option) => _defaultSatisfies(items[index], option))) return false;
        } else if (!_defaultSatisfies(items[index], node.itemNode!)) {
          return false;
        }
      }
      break;
    case 'string':
      final text = value as String;
      final length = codePointLength(text);
      if (node.minLength != null &&
          _compareNumbers(length, node.minLength) < 0) {
        return false;
      }
      if (node.maxLength != null &&
          _compareNumbers(length, node.maxLength) > 0) {
        return false;
      }
      if (node.pattern != null && node.pattern!.isNotEmpty) {
        if (!RegExp(node.pattern!).hasMatch(text)) return false;
      }
      break;
  }

  if (node.type == 'int' || node.type == 'number') {
    if (node.minimum != null && _compareNumbers(value, node.minimum) < 0) return false;
    if (node.maximum != null && _compareNumbers(value, node.maximum) > 0) return false;
  }
  if (node.hasConst && !_sameValue(node.constValue, value)) return false;
  if (node.enumValues != null &&
      !node.enumValues!.any((option) => _sameValue(option, value))) {
    return false;
  }
  return true;
}

bool _typeMatches(String type, Object? value) => switch (type) {
      'any' || 'union' => true,
      'string' => value is String,
      'bool' => value is bool,
      'int' => value is int || value is BigInt,
      'number' => _isNumberValue(value) && !_isNonFinite(value),
      'null' => value == null,
      'object' => value is Map<String, Object?>,
      'array' => value is List<Object?>,
      _ => true,
    };

bool _isNonFinite(Object? value) => value is double && !value.isFinite;

bool _withinExactRange(Object? value) {
  final big = _toBigInt(value);
  return big >= DescriptorGrammar.minExactInt && big <= DescriptorGrammar.maxExactInt;
}

/// Escapes one JSON Pointer token.
String escapePointerToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');
