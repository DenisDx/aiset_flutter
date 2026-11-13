/// The revision model of `SPEC.md` amendment 8.
///
/// Three revisions are mandatory and each answers a
/// different question:
///
/// * **source revision** — which bytes the authoritative store holds.
///   `sha256:` plus the first 32 hexadecimal characters of the SHA-256 of
///   the stored UTF-8 text, byte order mark included. This is
///   the baseline's `revision_of_bytes` and therefore the compare-and-set
///   token both implementations accept.
/// * **descriptor revision** — which descriptor the document was
///   validated against (`descriptorRevision` of the descriptor source).
/// * **active revision** — which revision the application is actually running
///   on. It advances only when a `live` change takes effect or the host
///   confirms a reload or restart, which is what makes
///   "stored and active differ" observable (`SPEC.md` amendment 8, APP-01).
///
/// On top of those, the section demands that the
/// internal **layer**, **resolver** and **registry** revisions be
/// captured when a candidate is prepared and verified before the commit. They are
/// computed here from a canonical rendering of the inputs, and that
/// rendering names variables and layers — never values — so a
/// revision can be logged and sent to a client without
/// disclosing a secret (`SPEC.md` amendments 6 and 26, SEC-01).
///
/// [RevisionSnapshot] is the pair-plus-internal-revisions object a client
/// presents with a write.
library;

import 'dart:convert';

import '../descriptor/descriptor.dart';
import '../resolver/resolver.dart';

/// The source revision of stored [text]: `sha256:` plus the first 32 hex
/// characters of the SHA-256 of its UTF-8 bytes.
///
/// A byte order mark is part of the stored bytes and therefore of
/// the revision: the same document saved with and without a BOM is
/// a different revision in both implementations.
String sourceRevisionOfText(String text) => descriptorRevision(text);

/// The source revision of the stored bytes [bytes].
String sourceRevisionOfBytes(List<int> bytes) =>
    'sha256:${sha256Hex(bytes).substring(0, 32)}';

/// A canonical rendering of [value] for hashing: keys in
/// the order given, UTF-8, no whitespace.
///
/// `jsonEncode` walks a Dart map in insertion order, so building the
/// map in a fixed order makes the digest independent of the machine
/// and of key hash randomization.
String canonicalDigestInput(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return <String, Object?>{for (final e in entries) '${e.key}': _canonical(e.value)};
  }
  if (value is List) return [for (final item in value) _canonical(item)];
  return value;
}

/// The revision of the canonical rendering of [value].
String revisionOfCanonical(Object? value) =>
    'sha256:${sha256Hex(utf8.encode(canonicalDigestInput(value))).substring(0, 32)}';

/// The revision of the mounted layer stack.
///
/// A layer is named by its owner and the source revision of the text it
/// contributes, in mount order; reordering the same
/// layers is therefore a different revision, while an
/// unchanged stack always yields the same one. A layer's
/// values are not part of the digest.
String computeLayerRevision(List<MountLayer> layers) => revisionOfCanonical([
      for (final layer in layers)
        {'owner': layer.owner, 'target': layer.target, 'revision': layer.sourceRevision},
    ]);

/// The revision of the resolver's injected layers.
///
/// Each layer contributes the sorted list of variable names it
/// answers for. The values deliberately do not take part:
/// an environment value may be a secret, and provenance already
/// establishes the rule that a name is recorded where a value
/// would not be. A candidate prepared against names that
/// disappeared before the commit is stale, which is what the section
/// asks the check to catch.
String computeResolverRevision(Resolver resolver) => revisionOfCanonical({
      'override': (resolver.overrides.keys.toList()..sort()),
      'environment': (resolver.environment.keys.toList()..sort()),
      'dotenv': (resolver.dotenv.keys.toList()..sort()),
    });

/// The revision of the trusted registry.
///
/// [bindings] are the names of the descriptor hooks and semantic
/// validators this build can execute, and [hosts] the
/// identities of the host callbacks that are installed. A
/// change to either changes what a prepared candidate means, so the
/// pipeline treats it exactly as a stale source revision.
String computeRegistryRevision({
  List<String> bindings = const [],
  List<String> hosts = const [],
}) =>
    revisionOfCanonical({
      'bindings': (bindings.toList()..sort()),
      'hosts': (hosts.toList()..sort()),
    });

/// The pair a revision-bound operation must present: the source
/// revision it read and the descriptor revision it validated against
/// (`SPEC.md` amendment 8).
///
/// An incomplete pair is not a conflict but a missing precondition:
/// the pipeline answers `REVISION_REQUIRED`.
final class RevisionPair {
  /// Creates the pair a client presents.
  const RevisionPair({this.source, this.descriptor});

  /// The source revision the client read, or `null` when it sent none.
  final String? source;

  /// The descriptor revision the client validated against, or `null`.
  final String? descriptor;

  /// Whether both halves are present and non-empty.
  bool get isComplete =>
      source != null && source!.isNotEmpty && descriptor != null && descriptor!.isNotEmpty;

  /// The pair the current state of [document] and [descriptor] calls for.
  factory RevisionPair.of({
    required String documentSourceRevision,
    required CompiledDescriptor descriptor,
  }) =>
      RevisionPair(
        source: documentSourceRevision,
        descriptor: descriptor.revision,
      );

  /// The envelope form.
  Map<String, Object?> toMap() => {
        'source_revision': source,
        'descriptor_revision': descriptor,
      };

  @override
  String toString() => 'RevisionPair(${source ?? '<absent>'}, ${descriptor ?? '<absent>'})';
}

/// Everything the pipeline captured when it prepared a candidate.
///
/// [RevisionSnapshot] holds the revision pair, the internal
/// layer/resolver/registry revisions of the same moment, the candidate source
/// text and the paths it changes. The commit re-checks
/// the snapshot against the store before it writes, which is
/// the "recheck snapshot" stage of the mandatory
/// order and the reason a long pre-commit probe cannot hold a storage
/// lock (`SPEC.md` amendments 8 and 9).
final class RevisionSnapshot {
  /// Creates a snapshot.
  const RevisionSnapshot({
    required this.pair,
    required this.layers,
    required this.resolver,
    required this.registry,
    required this.candidateSource,
    required this.changedPaths,
  });

  /// The pair the client presented.
  final RevisionPair pair;

  /// The layer revision when the candidate was prepared.
  final String layers;

  /// The resolver revision when the candidate was prepared.
  final String resolver;

  /// The registry revision when the candidate was prepared.
  final String registry;

  /// The candidate source text the pipeline produced.
  final String candidateSource;

  /// The pointers the candidate changes.
  final List<String> changedPaths;

  @override
  String toString() =>
      'RevisionSnapshot(${pair.source}, descriptor ${pair.descriptor}, '
      '${changedPaths.length} changed paths)';
}

/// One mounted layer of a configuration (`SPEC.md` amendment 7).
///
/// A layer is a base document contributed by a named owner at a
/// descriptor coordinate. The host defines the list and its
/// order; the library imposes no universal policy.
final class MountLayer {
  /// Creates a layer.
  const MountLayer({
    required this.owner,
    required this.target,
    required this.source,
  });

  /// The plugin or component that contributes the layer.
  final String owner;

  /// The descriptor coordinate the layer mounts at, e.g. `/plugins/x`.
  final String target;

  /// The layer's stored document text.
  final String source;

  /// The source revision of [source].
  String get sourceRevision => sourceRevisionOfText(source);

  @override
  String toString() => 'MountLayer($owner at $target)';
}
