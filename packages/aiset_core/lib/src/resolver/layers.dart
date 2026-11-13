part of 'resolver.dart';

/// The layer that supplied a variable's value.
enum VariableSource {
  /// The explicit host override layer.
  override('override'),

  /// The environment mapping the host injected.
  environment('env'),

  /// The `.env`-style mapping the host injected.
  dotenv('dotenv'),

  /// The placeholder's own `:-` fallback.
  inlineDefault('inline_default'),

  /// Nothing supplied the variable and it declared no fallback.
  empty('empty');

  const VariableSource(this.label);

  /// The name recorded in provenance and accepted on the wire.
  final String label;
}

/// The result of one variable lookup.
final class VariableLookup {
  /// Creates a lookup result.
  const VariableLookup(this.value, this.source);

  /// The text that will be substituted. Never `null`; an
  /// unset variable with no fallback is the empty string.
  final String value;

  /// The layer the value came from.
  final VariableSource source;

  @override
  String toString() => 'VariableLookup($value, ${source.label})';
}

/// The value layers a resolution may read.
///
/// Every mapping is supplied by the host; the constructor has no default
/// that consults the machine. Precedence is
/// [overrides] → [environment] → [dotenv] → the placeholder's inline
/// fallback (`SPEC.md` amendment 6). A mapping that holds the empty
/// string for a name does not answer for a placeholder that declares a
/// fallback: an empty value is treated as unset at that layer, and the search
/// continues down the chain.
final class Resolver {
  /// Creates a resolver over the given injected layers.
  const Resolver({
    this.overrides = const <String, String>{},
    this.environment = const <String, String>{},
    this.dotenv = const <String, String>{},
  });

  /// Explicit host-supplied values; the highest precedence.
  final Map<String, String> overrides;

  /// The environment mapping the host injected. Never the process
  /// environment.
  final Map<String, String> environment;

  /// A `.env`-style mapping the host injected.
  final Map<String, String> dotenv;

  static final RegExp _namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Whether [name] is a variable name the grammar accepts.
  static bool isValidName(String name) => _namePattern.hasMatch(name);

  /// The value of [name], searching the injected layers in precedence order.
  ///
  /// [inlineDefault] is the placeholder's `:-` fallback, or `null` when the
  /// placeholder declares none — the two are different: with a fallback an
  /// empty value at one layer continues the search, without one it stops
  /// there and reports that layer as the source.
  VariableLookup lookup(String name, {String? inlineDefault}) {
    for (final step in const [
      VariableSource.override,
      VariableSource.environment,
      VariableSource.dotenv,
    ]) {
      final value = _layer(step)[name];
      if (value == null) continue;
      if (value.isNotEmpty) return VariableLookup(value, step);
      // An empty value with a fallback declared continues the chain;
      // without one it is the answer, attributed to this layer.
      if (inlineDefault == null) return VariableLookup('', step);
    }
    if (inlineDefault != null) {
      return VariableLookup(inlineDefault, VariableSource.inlineDefault);
    }
    return const VariableLookup('', VariableSource.empty);
  }

  Map<String, String> _layer(VariableSource source) => switch (source) {
        VariableSource.override => overrides,
        VariableSource.environment => environment,
        VariableSource.dotenv => dotenv,
        VariableSource.inlineDefault || VariableSource.empty =>
          const <String, String>{},
      };

  /// Which of [names] are actually set, without exposing values.
  ///
  /// A name the grammar does not accept is left out of the answer rather than
  /// reported as unset, so a caller cannot mistake a malformed
  /// request for a missing variable.
  Map<String, bool> presence(Iterable<String> names) {
    final out = <String, bool>{};
    for (final name in names) {
      if (!isValidName(name)) continue;
      final source = lookup(name).source;
      out[name] = source == VariableSource.override ||
          source == VariableSource.environment ||
          source == VariableSource.dotenv;
    }
    return out;
  }
}
