part of 'pipeline.dart';

/// The eight permissions the service gates operations on
/// (`SPEC.md` amendments 8, 9 and 11).
///
/// They are the baseline's set, kept name-for-name because a
/// host's access policy is written against them and a remote
/// `aiset_service` backend reports them in its envelope.
abstract final class AisetPermission {
  /// May read the stored source text.
  static const String readSource = 'settings_read_source';

  /// May read the effective (resolved) view.
  static const String readEffective = 'settings_read_effective';

  /// May run a validation without writing.
  static const String validate = 'settings_validate';

  /// May write.
  static const String write = 'settings_write';

  /// May read a value under a `secret` node.
  static const String readSecret = 'settings_read_secret';

  /// May edit a value under a `secret` node.
  static const String editSecret = 'settings_edit_secret';

  /// May request the last known good backup.
  static const String loadLkg = 'settings_load_lkg';

  /// May read the raw descriptor document.
  static const String descriptorRaw = 'settings_descriptor_raw';

  /// Every permission name.
  static const Set<String> all = {
    readSource,
    readEffective,
    validate,
    write,
    readSecret,
    editSecret,
    loadLkg,
    descriptorRaw,
  };
}

/// An authenticated actor and the set of [AisetPermission] names it holds
/// (`SPEC.md` amendment 8).
///
/// The pipeline asks a principal for its permissions and nothing else: an
/// anonymous call is refused with `UNAUTHORIZED` before any document is
/// touched, and a call that lacks a permission is refused with
/// `FORBIDDEN` rather than downgraded to a partial answer.
final class Principal {
  /// Creates a principal with an explicit permission set.
  const Principal(this.id, this.permissions);

  /// The fully-permitted principal of a single-user local demo. A production
  /// host builds its principal from its own authentication layer.
  factory Principal.demo({String id = 'local-demo'}) =>
      Principal(id, AisetPermission.all);

  /// A principal with no permissions at all; the shape a
  /// read-only surface or an anonymous caller gets.
  factory Principal.none(String id) => Principal(id, const <String>{});

  /// The actor identifier, recorded in the audit log.
  final String id;

  /// The held permission names.
  final Set<String> permissions;

  /// Whether [permission] is held.
  bool has(String permission) => permissions.contains(permission);

  /// The same principal with [extra] permissions added.
  Principal withPermissions(Iterable<String> extra) =>
      Principal(id, {...permissions, ...extra});

  /// The same principal with [drop] permissions removed.
  Principal withoutPermissions(Iterable<String> drop) =>
      Principal(id, permissions.difference(drop.toSet()));

  @override
  String toString() => 'Principal($id, ${permissions.length} permissions)';
}

/// One registered document: its storage, its compiled descriptor and the
/// resolver that answers its placeholders (`SPEC.md` amendments 2 and 14).
///
/// A registration is created by the host at bootstrap and is the only way a
/// document id becomes addressable; a user-facing API takes a
/// [documentId], never a file path. The resolver is injected — nothing here
/// reads a process environment (`SPEC.md` amendment 6).
final class AisetDocumentRegistration {
  /// Registers one document.
  AisetDocumentRegistration({
    required this.documentId,
    required this.storage,
    required this.descriptorSource,
    this.resolver = const Resolver(),
    this.typedefSources = const [],
    this.fragments = const [],
    this.layers = const [],
    this.allowSingleWriterStorage = false,
  }) : descriptor = compileDescriptor(
          descriptorSource,
          typedefSources: typedefSources,
          fragments: fragments,
        );

  /// The addressable identifier.
  final String documentId;

  /// The authoritative storage of the document.
  final AisetStorage storage;

  /// The descriptor source text.
  final String descriptorSource;

  /// The compiled descriptor.
  final CompiledDescriptor descriptor;

  /// The injected value layers for this document.
  final Resolver resolver;

  /// The typedef sources the descriptor was compiled from.
  final List<String> typedefSources;

  /// The descriptor fragments mounted into it.
  final List<DescriptorFragment> fragments;

  /// The mounted data layers, highest precedence first
  /// (`SPEC.md` amendment 7). The host defines the list and its order; the
  /// library imposes no universal policy.
  final List<MountLayer> layers;

  /// Whether the host explicitly accepted a storage adapter
  /// with no conditional write.
  ///
  /// A legacy single-writer adapter is allowed only as an explicitly
  /// limited mode that must not claim concurrency protection
  /// (`SPEC.md` amendment 10). Without this flag the pipeline refuses to
  /// write through an adapter that cannot do a conditional write, rather
  /// than quietly hoping no second controller exists.
  final bool allowSingleWriterStorage;

  /// The revision of the mounted layer stack.
  String get layersRevision => computeLayerRevision(layers);

  @override
  String toString() =>
      'AisetDocumentRegistration($documentId, descriptor ${descriptor.revision})';
}

/// A prepared, immutable view of one document: the four views of
/// `SPEC.md` amendment 2 plus the revisions and the issues that describe it.
///
/// A snapshot is a value. Every tree it exposes is built fresh for the
/// snapshot and the snapshot is never mutated by a
/// consumer's write to a returned map, because the maps handed out are
/// the pipeline's own — changes go through
/// [AisetService.applyOperations] (`SPEC.md` amendment 2: "a snapshot
/// MUST be immutable from the consumer's point of view").
final class AisetSnapshot {
  /// Creates a snapshot.
  AisetSnapshot({
    required this.documentId,
    required String sourceText,
    required this.storedTree,
    required this.effectiveTree,
    required this.activeTree,
    required this.provenance,
    required this.sourceRevision,
    required this.descriptorRevision,
    required this.activeRevision,
    required this.layersRevision,
    required this.resolverRevision,
    required this.registryRevision,
    List<AisetIssue> issues = const [],
    this.loadedFrom = 'file',
    this.invalidOnDisk = false,
    this.invalidReason = '',
    this.rawSourceVisible = true,
    Json5Document? document,
  })  : issues = List<AisetIssue>.unmodifiable(issues),
        _rawSourceText = sourceText,
        _document = document ?? Json5Document(sourceText, origin: documentId);

  /// The registered document id.
  final String documentId;

  /// The stored source text — the original JSON5 with its comments,
  /// placeholders and formatting.
  ///
  /// Throws `SECRET_ACCESS_DENIED` on the authorized copy a principal
  /// without the secret read permission receives: that text holds every
  /// declared secret of the document verbatim, so reading it would
  /// defeat the redaction applied to the value views
  /// (`SPEC.md` amendments 2, 11 and 26, SEC-01). The revisions
  /// of the copy stay exact because a hash is not a
  /// value, and [storedAt]/[effectiveAtPointer] answer the
  /// non-secret paths.
  String get sourceText {
    if (!rawSourceVisible) {
      throw AisetFailure(
        AisetErrorCode.secretAccessDenied,
        'This document declares a secret subtree that is not available to '
            'this principal; its source text is therefore not returned',
      );
    }
    return _rawSourceText;
  }

  final String _rawSourceText;

  /// The stored value tree, with placeholders kept as [TemplateRef].
  ///
  /// A placeholder is data here, never a secret: the document declares
  /// `${VAR}`, and only the resolution knows what answered it
  /// (`SPEC.md` amendment 3 write rule 5).
  final Object? storedTree;

  /// The effective view: defaults materialized, placeholders resolved.
  final Object? effectiveTree;

  /// The active view: what the application is running on. It equals
  /// [effectiveTree] once a `live` change is applied or the host confirms a
  /// reload; until then it lags behind, which is exactly the difference
  /// APP-01 asks to be observable.
  final Object? activeTree;

  /// Provenance by pointer. It names variables and layers, never values.
  final Map<String, Provenance> provenance;

  /// The revision of [sourceText].
  final String sourceRevision;

  /// The revision of the descriptor this snapshot was validated against.
  final String descriptorRevision;

  /// The revision the application is running on.
  final String activeRevision;

  /// The internal layer revision captured with this snapshot.
  final String layersRevision;

  /// The internal resolver revision captured with this snapshot.
  final String resolverRevision;

  /// The internal registry revision captured with this snapshot.
  final String registryRevision;

  /// The issues that describe this state; empty for a healthy document.
  final List<AisetIssue> issues;

  /// Where the state came from: `file`, `memory`, `lkg`,
  /// `invalid` or `absent`.
  final String loadedFrom;

  /// Whether the authoritative source currently holds a document this engine
  /// refuses to load.
  final bool invalidOnDisk;

  /// The reason [invalidOnDisk] is set, as rule names and pointers — never a
  /// value.
  final String invalidReason;

  /// Whether [sourceText] is the authoritative document text.
  ///
  /// It is false only on an authorized copy built for a principal that
  /// may not read a declared secret subtree: the raw text of such
  /// a document holds that secret verbatim, so
  /// exposing it would defeat the permission the value views were
  /// redacted for. [AisetService.readSource] answers
  /// `SECRET_ACCESS_DENIED` for exactly the same case, and the
  /// revisions of the document stay correct here because
  /// they are hashes and not values (`SPEC.md` amendments 2, 11 and 26).
  final bool rawSourceVisible;

  /// The parsed document behind [sourceText], for pointer navigation and
  /// source slices. It is derived from [sourceText] and holds no state of
  /// its own. Guarded by the same rule as [sourceText].
  Json5Document get document {
    if (!rawSourceVisible) {
      throw AisetFailure(
        AisetErrorCode.secretAccessDenied,
        'The source tree of a document with an inaccessible secret is not returned',
      );
    }
    return _document;
  }
  final Json5Document _document;

  /// The revision pair a write must present for this snapshot.
  RevisionPair get revisionPair => RevisionPair(
        source: sourceRevision,
        descriptor: descriptorRevision,
      );

  /// The stored value at [pointer], or [resolverMissing] when absent.
  Object? storedAt(String pointer) => lookupStored(storedTree, pointer);

  /// The effective value at [pointer], or [resolverMissing] when absent.
  Object? effectiveAtPointer(String pointer) => lookupStored(effectiveTree, pointer);

  /// The same snapshot with [newActiveRevision] and [newActiveTree]: the
  /// revision the application confirmed it is running on.
  AisetSnapshot withActive({
    required String newActiveRevision,
    required Object? newActiveTree,
  }) =>
      AisetSnapshot(
        documentId: documentId,
        sourceText: _rawSourceText,
        storedTree: storedTree,
        effectiveTree: effectiveTree,
        activeTree: newActiveTree,
        provenance: provenance,
        sourceRevision: sourceRevision,
        descriptorRevision: descriptorRevision,
        activeRevision: newActiveRevision,
        layersRevision: layersRevision,
        resolverRevision: resolverRevision,
        registryRevision: registryRevision,
        issues: issues,
        loadedFrom: loadedFrom,
        invalidOnDisk: invalidOnDisk,
        invalidReason: invalidReason,
        rawSourceVisible: rawSourceVisible,
        document: _document,
      );

  @override
  String toString() =>
      'AisetSnapshot($documentId @ $sourceRevision, $loadedFrom'
      '${invalidOnDisk ? ', INVALID ON DISK' : ''})';
}

/// Reads [path] out of a stored or effective tree.
///
/// A numeric token addresses an array item only inside a list, so an object
/// key of `"0"` is never mistaken for an index (`SPEC.md` amendment 4).
Object? lookupStored(Object? tree, String path) {
  Object? node = tree;
  for (final token in parsePointer(path)) {
    if (isObjectValue(node)) {
      final map = (node! as Map<Object?, Object?>).cast<Object?, Object?>();
      if (!mapHas(map, token)) return resolverMissing;
      node = map[token];
    } else if (node is List) {
      final index = indexValue(token);
      if (!isIndexToken(token) || index == null || index >= node.length) {
        return resolverMissing;
      }
      node = node[index];
    } else {
      return resolverMissing;
    }
  }
  return node;
}
