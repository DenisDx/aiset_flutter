part of 'descriptor.dart';

/// The descriptor envelope version this compiler understands.
const String descriptorVersion = '1.0';

/// The append-style marker is not part of descriptor grammar; pointers
/// here are plain JSON Pointers (`SPEC.md` amendment 4).

/// Vocabulary of the descriptor grammar (`SPEC.md` amendment 5).
///
/// These names are the compatibility surface: a descriptor
/// written for the other implementation must mean the same
/// thing here, so the sets are pinned by the corpus rather than renamed.
abstract final class DescriptorGrammar {
  /// Types a node may declare directly.
  static const Set<String> primitiveTypes = {
    'string', 'int', 'number', 'bool', 'null', 'object', 'array', 'union', 'any',
  };

  /// Values the `apply` policy may take.
  static const Set<String> applyValues = {'live', 'reload', 'restart'};

  /// Conversions `env.convert` may name.
  static const Set<String> convertValues = {'string', 'int', 'number', 'bool'};

  /// Lifecycle events a hook binding may attach to. Execution of hooks is not
  /// implemented by either product yet (`SPEC_.md` amendment 33); the
  /// grammar is declared so a descriptor stays readable.
  static const Set<String> hookEvents = {
    'before_create', 'before_update', 'after_create', 'after_update',
  };

  /// Actions a helper may offer.
  static const Set<String> helperActions = {'create', 'edit'};

  /// Presentations a helper may request.
  static const Set<String> helperPresentations = {'modal', 'wizard'};

  /// Scopes a hook binding may claim.
  static const Set<String> hookScopes = {'node', 'subtree'};

  /// Keys of the descriptor envelope. `x_aiset_flutter` is this product's
  /// namespaced extension (`SPEC.md` amendment 5) and is therefore
  /// known here, not unknown metadata.
  static const Set<String> envelopeKeys = {
    'descriptor_version',
    'project',
    'config_version',
    'root',
    'x_aiset_flutter',
  };

  /// The envelope key holding the version string.
  static const String versionKey = 'descriptor_version';

  /// The envelope key holding the root node.
  static const String rootKey = 'root';

  /// Keys of an `env` policy object.
  static const Set<String> envKeys = {'allowed', 'convert'};

  /// Keys of a `ui` object.
  static const Set<String> uiKeys = {
    'label', 'group', 'order', 'help', 'widget', 'rows', 'placeholder',
  };

  /// Keys of a `helper` object.
  static const Set<String> helperKeys = {
    'tag', 'actions', 'presentation', 'settings',
  };

  /// Keys of a hook binding object.
  static const Set<String> bindingKeys = {'tag', 'scope', 'settings'};

  /// Keys of the wrapper form of `description` and `title`
  /// (`SPEC_.md` amendment 41).
  static const Set<String> localizedTextKeys = {'default', 'text'};

  /// Node properties that build a composite value.
  static const Set<String> compositeKeys = {
    'children', 'children_options', 'additional_children',
  };

  /// Node properties that govern object keys.
  static const Set<String> keyConstraintKeys = {'key_pattern', 'key_enum'};

  /// Constraints that apply only to certain types, and the
  /// types each one applies to (`SPEC.md` amendment 5:
  /// "constraints inappropriate for scalar types are forbidden").
  static const Map<String, Set<String>> constraintTypes = {
    'min_length': {'string'},
    'max_length': {'string'},
    'pattern': {'string'},
    'minimum': {'int', 'number'},
    'maximum': {'int', 'number'},
    'min_items': {'array'},
    'max_items': {'array'},
    'unique_items': {'array'},
  };

  /// The declared type of every node property.
  ///
  /// `default` and `const` hold an arbitrary JSON value and are checked
  /// against the node instead of against a type.
  /// `description` and `title` accept the two forms of `SPEC_.md`
  /// amendment 41.
  static const Map<String, PropertyType> propertyTypes = {
    'type': PropertyType.text,
    'description': PropertyType.textOrLocalized,
    'title': PropertyType.textOrLocalized,
    'required': PropertyType.boolean,
    'nullable': PropertyType.boolean,
    'enum': PropertyType.list,
    'minimum': PropertyType.number,
    'maximum': PropertyType.number,
    'min_length': PropertyType.integer,
    'max_length': PropertyType.integer,
    'pattern': PropertyType.text,
    'min_items': PropertyType.integer,
    'max_items': PropertyType.integer,
    'unique_items': PropertyType.boolean,
    'children': PropertyType.mapOrText,
    'id': PropertyType.text,
    'children_options': PropertyType.list,
    'additional_children': PropertyType.map,
    'key_pattern': PropertyType.text,
    'key_enum': PropertyType.list,
    'env': PropertyType.map,
    'secret': PropertyType.boolean,
    'read_only': PropertyType.boolean,
    'apply': PropertyType.text,
    'validators': PropertyType.list,
    'ui': PropertyType.map,
    'helper': PropertyType.map,
    'hooks': PropertyType.map,
    'typedef': PropertyType.text,
  };

  /// Every node property the grammar knows.
  static Set<String> get nodeKeys => propertyTypes.keys.toSet();

  /// The largest integer a settings document may hold exactly on every
  /// platform (`docs/grammars.md` §2.1).
  static final BigInt maxExactInt = BigInt.parse('9007199254740991');

  /// The smallest integer a settings document may hold exactly on every
  /// platform (`docs/grammars.md` §2.1).
  static final BigInt minExactInt = BigInt.parse('-9007199254740991');
}

/// The value shape a descriptor property accepts.
enum PropertyType {
  /// A JSON string.
  text,

  /// A JSON string, or the localized-text wrapper of `SPEC_.md` 41.
  textOrLocalized,

  /// A JSON boolean.
  boolean,

  /// A JSON array.
  list,

  /// A JSON object.
  map,

  /// A JSON object or a string naming a template.
  mapOrText,

  /// A JSON number that is an integer.
  integer,

  /// Any JSON number.
  number,
}

/// Whether [value] has the shape [type] declares.
bool matchesPropertyType(PropertyType type, Object? value) => switch (type) {
      PropertyType.text => value is String,
      PropertyType.boolean => value is bool,
      PropertyType.list => value is List<Object?>,
      PropertyType.map => value is Map<String, Object?>,
      PropertyType.mapOrText =>
        value is Map<String, Object?> || value is String,
      PropertyType.integer => _isExactInteger(value),
      PropertyType.number => _isNumeric(value),
      PropertyType.textOrLocalized =>
        value is String || value is Map<String, Object?>,
    };

bool _isExactInteger(Object? value) => switch (value) {
      int() => true,
      BigInt() => true,
      final double v => v.isFinite && v == v.truncateToDouble(),
      _ => false,
    };

bool _isNumeric(Object? value) =>
    value is int || value is BigInt || value is double;
