part of 'resolver.dart';

/// Where an effective value came from (`SPEC.md` amendment 6).
enum ProvenanceKind {
  /// The value is stored in the document itself.
  file('file'),

  /// The value was supplied by a variable layer.
  environment('environment'),

  /// The value was materialized from the descriptor default.
  defaultValue('default'),

  /// The value came from a mounted layer rather than the document.
  layer('layer');

  const ProvenanceKind(this.label);

  /// The name recorded and sent on the wire.
  final String label;
}

/// Provenance of one effective value, keyed by its pointer in the
/// document.
///
/// A provenance entry names variables and layers, never values, so a
/// secret can be described without being disclosed
/// (`SPEC.md` amendments 6 and 26, SEC-01).
final class Provenance {
  /// Creates a provenance entry.
  const Provenance({
    required this.kind,
    this.variable,
    this.variables,
    this.source,
    this.layer,
  });

  /// The kind of origin.
  final ProvenanceKind kind;

  /// The first variable that contributed, when the value came from a layer.
  final String? variable;

  /// Every variable that contributed, in the order they appear in the text.
  ///
  /// Present only when a value was built from more than one reference: a
  /// single-variable entry keeps the shape the other
  /// implementation and the tree consumers already produce. Recording
  /// only the last contributor would attribute an override to the
  /// environment (`SPEC_.md` amendment 38, report A22).
  final List<String>? variables;

  /// The supplying layer, omitted when it is the plain environment.
  final VariableSource? source;

  /// The owning layer, for a value that came from a mounted layer.
  final String? layer;

  /// Provenance for a value stored in the document.
  const Provenance.file()
      : kind = ProvenanceKind.file,
        variable = null,
        variables = null,
        source = null,
        layer = null;

  /// Provenance for a materialized descriptor default.
  const Provenance.defaulted()
      : kind = ProvenanceKind.defaultValue,
        variable = null,
        variables = null,
        source = null,
        layer = null;

  /// Provenance for one resolved variable.
  Provenance.environment(String name, VariableSource from)
      : kind = ProvenanceKind.environment,
        variable = name,
        variables = null,
        source = from == VariableSource.environment ? null : from,
        layer = null;

  /// Provenance for a text value built from several variables.
  Provenance.fromVariables(List<String> names, VariableSource highestPrecedence)
      : kind = ProvenanceKind.environment,
        variable = names.isEmpty ? null : names.first,
        variables = names.length > 1 ? List.unmodifiable(names) : null,
        source = highestPrecedence == VariableSource.environment
            ? null
            : highestPrecedence,
        layer = null;

  /// The recorded shape: the keys the tree and the HTTP envelope carry.
  Map<String, Object?> toMap() => {
        'kind': kind.label,
        if (variable != null) 'variable': variable,
        if (variables != null) 'variables': variables,
        if (source != null) 'source': source!.label,
        if (layer != null) 'layer': layer,
      };

  @override
  String toString() => 'Provenance(${toMap()})';
}
