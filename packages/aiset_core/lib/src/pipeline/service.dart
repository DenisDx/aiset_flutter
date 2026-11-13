part of 'pipeline.dart';

/// The service: registration, the read views and the single write pipeline
/// (`SPEC.md` amendments 8, 9, 10, 11 and 14).
///
/// One document, one authoritative source, one write path. Everything that
/// changes a stored configuration goes through [applyOperations] — the
/// editor's draft, an AI proposal, a doctor repair, a host integration — and
/// the pipeline order is the amendment's:
///
/// ```text
/// authorize → revisions → candidate → resolve → validate → preserve
///           → probe → recheck → commit → apply → audit
/// ```
///
/// Three properties the acceptance IDs test:
///
/// * **A dry run or any pre-commit failure leaves the source
///   byte-for-byte unchanged** (`SPEC.md` amendment 3 write rule 7). Nothing
///   before **commit** touches the store, and nothing after it can be
///   undone by a later stage.
/// * **A successful save is not a successful runtime apply.** A failed
///   application handler answers `stored = true` with `apply_failed`; the
///   library never presents a written file as unsaved (`SPEC.md` amendment 8,
///   APP-01).
/// * **The revision pair is a precondition, not an optimisation.** An absent
///   pair is `REVISION_REQUIRED` and a stale one is `REVISION_CONFLICT`;
///   the store is re-read and the exact candidate re-validated immediately
///   before the conditional write, so a long pre-commit probe cannot let a
///   stale candidate win.
///
/// Writes are serialized inside one service by a single in-isolate
/// [Completer]-based lock. That is deliberately NOT sold as
/// cross-context concurrency: such a claim belongs to an adapter that provides
/// compare-and-swap and declares the capability (`SPEC.md` amendments 8 and
/// 10, STO-01), and the pipeline refuses to write through an adapter that
/// declares no conditional write at all unless the host explicitly
/// accepted that limited single-writer mode.
///
/// A rejection is a value, not an exception: [applyOperations],
/// [setValue] and [validateValue] answer with an [AisetWriteResult] or
/// [AisetValidationResult] whose `failure` is the stable code. Only a
/// caller error — an unregistered document id, an anonymous
/// principal where one is required — throws [AisetFailure] before the
/// pipeline runs.
final class AisetService {
  /// Creates a service.
  AisetService({
    this.limits = Limits.defaultProfile,
    this.callbackTimeout = const Duration(seconds: 30),
    AuditSink? audit,
  }) : _auditSink = audit;

  /// The resource limits of every validation this service
  /// performs (`SPEC.md` amendment 26).
  final Limits limits;

  /// The bound on every host callback. A null value bounds nothing and is
  /// only correct in a test.
  final Duration? callbackTimeout;

  final AuditSink? _auditSink;
  final Map<String, AisetDocumentRegistration> _documents = {};
  final Map<String, AisetSnapshot> _states = {};
  final Map<String, Object?> _activeTrees = {};
  final SubscriptionRegistry _subscriptions = SubscriptionRegistry();
  final List<ProbeCallback> _probes = [];
  final List<AfterSaveCallback> _afterSave = [];
  final List<ApplicationCallback> _application = [];

  /// Serialize this service's writes. One isolate owns
  /// the write path; cross-context safety comes from the
  /// adapter's compare-and-swap, not from here.
  Future<void> _writeGate = Future<void>.value();

  // -- registration ---------------------------------------------------------

  /// Registers [registration] under its document id.
  ///
  /// The host owns the allowlist: a client addresses a
  /// registered id and never a file path (`SPEC.md` amendments 2 and 11).
  /// Registering an id again replaces it and drops the
  /// cached state, which is what a descriptor reload looks like.
  void register(AisetDocumentRegistration registration) {
    _documents[registration.documentId] = registration;
    _states.remove(registration.documentId);
    _activeTrees.remove(registration.documentId);
    _audit('register', {
      'document': registration.documentId,
      'descriptor_revision': registration.descriptor.revision,
      'mode': registration.storage.capabilities.mode.label,
    });
  }

  /// The registered documents, sorted.
  List<String> listDocuments({required Principal principal}) {
    _require(principal, AisetPermission.readSource);
    return _documents.keys.toList()..sort();
  }

  /// The registration of [documentId].
  ///
  /// Throws `NOT_FOUND` for an id that was never registered: a
  /// document this service does not know about is not a storage failure
  /// and not an empty document either (`SPEC.md` amendment 11).
  AisetDocumentRegistration registrationOf(String documentId) {
    final registration = _documents[documentId];
    if (registration == null) {
      throw AisetFailure(AisetErrorCode.notFound, 'Unknown document \'$documentId\'');
    }
    return registration;
  }

  /// The compiled descriptor of [documentId].
  CompiledDescriptor descriptorOf(String documentId) =>
      registrationOf(documentId).descriptor;

  /// The current revision pair of [documentId], which is what a
  /// client reads before it stages a write.
  Future<RevisionPair> revisionPair(String documentId, {required Principal principal}) async =>
      (await load(documentId, principal: principal)).revisionPair;

  // -- callbacks and subscriptions -------------------------------------------

  /// Installs a pre-commit probe, which may veto a candidate
  /// (`SPEC.md` amendment 9).
  void onProbeChanges(ProbeCallback callback) => _probes.add(callback);

  /// Installs a post-commit observer, which cannot cancel a committed
  /// result.
  void onAfterSave(AfterSaveCallback callback) => _afterSave.add(callback);

  /// Installs the host's domain application handler for `live`
  /// and `reload` changes.
  void onApplication(ApplicationCallback callback) => _application.add(callback);

  /// The callback identities the registry revision is
  /// computed from: installing or removing a host callback
  /// changes what a prepared candidate means, so the pipeline re-checks
  /// it the way it re-checks the descriptor.
  List<String> get _callbackIdentities => [
        for (var index = 0; index < _probes.length; index++) 'probe:$index',
        for (var index = 0; index < _afterSave.length; index++) 'after_save:$index',
        for (var index = 0; index < _application.length; index++) 'application:$index',
      ];

  /// The revision of the installed host callbacks and
  /// descriptor bindings.
  String registryRevisionOf(AisetDocumentRegistration registration) => computeRegistryRevision(
        bindings: _descriptorBindings(registration),
        hosts: _callbackIdentities,
      );

  /// The names of the descriptor bindings this build can execute.
  ///
  /// A hook binding is recognized and never executed
  /// (`SPEC.md` amendment 9), so a change under one is
  /// `UNSUPPORTED_CAPABILITY` rather than a silent success. A semantic
  /// validator name has to be in the registry for the descriptor to be
  /// usable at all; `SPEC_.md` 33 defers the hook dispatcher,
  /// so the binding set here is the honest one.
  List<String> _descriptorBindings(AisetDocumentRegistration registration) {
    final bindings = <String>{};
    void walk(DescriptorNode? node) {
      if (node == null) return;
      for (final name in node.validators) {
        bindings.add('validator:$name');
      }
      if (node.hooks != null) bindings.add('hook:${node.path}');
      for (final child in (node.children ?? const <String, DescriptorNode>{}).values) {
        walk(child);
      }
      walk(node.additionalChildren);
      for (final option in node.optionNodes ?? const <DescriptorNode>[]) {
        walk(option);
      }
      walk(node.itemNode);
    }

    walk(registration.descriptor.root);
    return bindings.toList()..sort();
  }

  /// Subscribes [listener] to changes under [paths] of one document.
  ///
  /// The returned handle cancels the registration. [principal] decides
  /// what the subscriber may see: a changed path inside a
  /// secret subtree the principal may not read is never delivered,
  /// so a subscription cannot become a channel for
  /// disclosing a secret (`SPEC.md` amendments 9 and 26, SEC-01).
  SubscriptionHandle subscribe(
    String documentId,
    List<String> paths,
    ChangeListener listener, {
    required Principal principal,
  }) {
    registrationOf(documentId);
    _require(principal, AisetPermission.readEffective);
    final registration = registrationOf(documentId);
    return _subscriptions.subscribe(documentId, paths, listener, permissionFilter: (changed) {
      if (principal.has(AisetPermission.readSecret)) return true;
      final node = registration.descriptor.nodeAt(changed);
      return !(subtreeHasSecret(node) || _underSecretSubtree(registration, changed));
    });
  }

  /// Whether [pointer] lies inside a secret subtree its own node
  /// declaration does not show.
  bool _underSecretSubtree(AisetDocumentRegistration registration, String pointer) {
    for (final prefix in pointerPrefixes(pointer)) {
      final node = registration.descriptor.nodeAt(prefix);
      if (node != null && node.secret) return true;
    }
    return false;
  }

  // -- reads ------------------------------------------------------------------

  /// The current snapshot of [documentId], read from the
  /// authoritative source and cached.
  ///
  /// Four different results are kept distinct, as amendment 11
  /// requires: an unregistered id (`NOT_FOUND`, thrown by
  /// [registrationOf]), an absent document (`NOT_FOUND` from the store), an
  /// invalid source (a snapshot with [AisetSnapshot.invalidOnDisk]
  /// set, which never authorizes a seed overwrite), and a
  /// storage failure (`STORAGE_ERROR`, propagated, never treated as
  /// absent).
  Future<AisetSnapshot> load(String documentId, {required Principal principal}) async {
    _require(principal, AisetPermission.readEffective);
    final cached = _states[documentId];
    if (cached != null) return _authorized(cached, principal);
    return _authorized(await _reload(documentId), principal);
  }

  /// Re-reads the authoritative source and adopts a valid external
  /// edit (`SPEC.md` amendment 11).
  Future<AisetSnapshot> reread(String documentId, {required Principal principal}) async {
    _require(principal, AisetPermission.readEffective);
    return _authorized(await _reload(documentId), principal);
  }

  Future<AisetSnapshot> _reload(String documentId) async {
    final registration = registrationOf(documentId);
    final stored = await registration.storage.read();
    final state = await buildSnapshot(
      registration: registration,
      sourceText: stored.sourceText,
      sourceRevision: stored.revision,
      activeTree: _activeTrees[documentId],
      activeRevision: _states[documentId]?.activeRevision ?? stored.revision,
      loadedFrom: stored.loadedFrom,
      limits: limits,
      registryRevision: registryRevisionOf(registration),
    );
    _states[documentId] = state;
    _activeTrees.putIfAbsent(documentId, () => state.effectiveTree);
    if (state.invalidOnDisk) {
      _audit('invalid_document', {'document': documentId, 'reason': state.invalidReason});
    }
    return state;
  }

  /// The stored, effective and active values at [pointer], with
  /// provenance (`SPEC.md` amendments 2, 4 and 6).
  ///
  /// A path inside a secret subtree is refused with
  /// `SECRET_ACCESS_DENIED` rather than answered with a redacted
  /// fragment: a redacted subtree would still disclose its shape.
  Future<AisetValueResult> get(
    String documentId,
    String pointer, {
    required Principal principal,
    bool effective = true,
  }) async {
    final registration = registrationOf(documentId);
    _require(principal, effective ? AisetPermission.readEffective : AisetPermission.readSource);
    final node = registration.descriptor.nodeAt(pointer);
    if (node == null && pointer.isNotEmpty) {
      throw AisetFailure(
          AisetErrorCode.notFound, 'Path \'$pointer\' is not declared by the descriptor');
    }
    final snapshot = await load(documentId, principal: principal);
    if (!principal.has(AisetPermission.readSecret) && subtreeHasSecret(node)) {
      throw AisetFailure(AisetErrorCode.secretAccessDenied,
          'Path \'$pointer\' contains an inaccessible secret; a redacted fragment is not '
          'returned');
    }
    final stored = lookupStored(snapshot.storedTree, pointer);
    final resolved = lookupStored(snapshot.effectiveTree, pointer);
    final active = lookupStored(snapshot.activeTree, pointer);
    // The exact source slice is part of the document
    // text, which a redacted copy does not expose: a
    // non-secret path under a document that declares a secret
    // elsewhere still reports its values, and its source text is simply
    // not available to this principal.
    final slice = snapshot.rawSourceVisible ? sourceSliceAt(snapshot.document, pointer) : null;
    final applied = !isMissing(stored) ? false : node?.hasDefault ?? false;
    // Absent with no default is not a value with an origin:
    // the position holds nothing, and inventing a
    // `file` provenance for it would read as a stored value.
    final provenance = isMissing(stored) && !applied
        ? null
        : snapshot.provenance[pointer] ??
            (applied
                ? const Provenance.defaulted()
                : (pointer.isEmpty ? const Provenance.file() : const Provenance.file()));
    return AisetValueResult(
      document: documentId,
      path: pointer,
      exists: !isMissing(stored),
      sourceText: slice,
      storedValue: stored,
      effective: isMissing(resolved) ? null : resolved,
      active: isMissing(active) ? null : active,
      defaultApplied: applied,
      provenance: provenance,
      revision: snapshot.sourceRevision,
      descriptorRevision: snapshot.descriptorRevision,
      applyPolicy: ApplyPolicy.tryParse(node?.apply) ?? ApplyPolicy.restart,
      readOnly: node?.readOnly ?? false,
      secret: node?.secret ?? false,
      required: node?.required ?? false,
      constValue: node?.hasConst ?? false,
    );
  }

  /// The whole-document [AisetSnapshot] as the principal may see
  /// it.
  ///
  /// A principal without the secret read permission
  /// receives a tree in which every secret subtree is absent, and one
  /// `secret_redacted` issue per redacted pointer naming the path and
  /// nothing else. The executed baseline hands the same
  /// effective tree to every authenticated principal, which
  /// defeats the permission (`SPEC_.md` 38, `SPEC.md`
  /// amendment 26 / SEC-01); the corrected view is what
  /// `SEC-01` requires, and the difference is pinned by the pipeline
  /// corpus.
  AisetSnapshot _authorized(AisetSnapshot snapshot, Principal principal) {
    if (principal.has(AisetPermission.readSecret)) return snapshot;
    final registration = registrationOf(snapshot.documentId);
    final redacted = <String>{};
    Object? filter(Object? value, String path) {
      if (isObjectValue(value)) {
        final map = (value! as Map<Object?, Object?>).cast<Object?, Object?>();
        final out = <String, Object?>{};
        for (final entry in map.entries) {
          final key = entry.key! as String;
          final childPath = '$path/${escapeToken(key)}';
          final child = registration.descriptor.nodeAt(childPath);
          if (child != null && child.secret) {
            // A secret node's whole subtree goes with it: the
            // compiler inherits `secret` into the descendants, so
            // the outermost secret pointer is the one reported.
            redacted.add(childPath);
            continue;
          }
          final kept = filter(entry.value, childPath);
          if (!isMissing(kept)) out[key] = kept;
        }
        return out;
      }
      if (value is List) {
        return [
          for (var index = 0; index < value.length; index++)
            filter(value[index], '$path/$index'),
        ];
      }
      return value;
    }

    final effective = filter(snapshot.effectiveTree, '');
    final active = filter(snapshot.activeTree, '');
    final stored = filter(snapshot.storedTree, '');
    // The filter runs over three views of the same
    // document; one redaction report per secret path.
    if (redacted.isEmpty) return snapshot;
    final paths = redacted.toList()..sort();
    return AisetSnapshot(
      documentId: snapshot.documentId,
      sourceText: snapshot.sourceText,
      storedTree: stored,
      effectiveTree: effective,
      activeTree: active,
      provenance: {
        for (final entry in snapshot.provenance.entries)
          if (!redacted.any((path) => _overlaps(entry.key, path))) entry.key: entry.value,
      },
      sourceRevision: snapshot.sourceRevision,
      descriptorRevision: snapshot.descriptorRevision,
      activeRevision: snapshot.activeRevision,
      layersRevision: snapshot.layersRevision,
      resolverRevision: snapshot.resolverRevision,
      registryRevision: snapshot.registryRevision,
      issues: [
        ...snapshot.issues,
        for (final path in paths)
          AisetIssue(
            rule: 'secret_redacted',
            path: path,
            message: 'A secret subtree is not available to this principal',
            severity: AisetSeverity.warning,
          ),
      ],
      loadedFrom: snapshot.loadedFrom,
      invalidOnDisk: snapshot.invalidOnDisk,
      invalidReason: snapshot.invalidReason,
      rawSourceVisible: false,
      document: snapshot.document,
    );
  }

  // -- the pipeline -----------------------------------------------------------

  /// The one write entry point: authorize, check revisions,
  /// build and validate one candidate, probe, recheck, commit, apply, audit.
  ///
  /// [operations] apply sequentially to a single candidate, so a later
  /// operation sees what an earlier one created —
  /// create-the-container-then-fill-it works inside one batch — and the whole
  /// batch is saved by one conditional write or not at all
  /// (`SPEC.md` amendment 8). It is not a distributed transaction and
  /// performs no rollback of external actions.
  ///
  /// [dryRun] stops the pipeline after the validation and
  /// preservation stages: it answers with the candidate text and the
  /// issues it would produce, runs no probe, writes nothing, and
  /// notifies nobody.
  Future<AisetWriteResult> applyOperations(
    String documentId,
    List<AisetOperation> operations, {
    required RevisionPair expected,
    required Principal principal,
    bool dryRun = false,
  }) async {
    final registration = registrationOf(documentId);
    // -- authorize ---------------------------------------------------------
    final permission = dryRun ? AisetPermission.validate : AisetPermission.write;
    if (!principal.has(permission)) {
      return _refused(registration,
          AisetFailure(AisetErrorCode.forbidden, 'Principal lacks the $permission permission'));
    }
    if (operations.isEmpty) {
      return _refused(registration,
          AisetFailure(AisetErrorCode.badRequest, 'At least one operation is required'));
    }
    // -- revisions ---------------------------------------------------------
    final state = _states[documentId] ?? await _reload(documentId);
    final revisionFailure = _checkPair(state, expected);
    if (revisionFailure != null) return _refused(registration, revisionFailure);

    final layers = registration.layersRevision;
    final resolver = computeResolverRevision(registration.resolver);
    final registry = registryRevisionOf(registration);

    // -- candidate → resolve → validate → preserve -------------------------
    final outcome = buildCandidate(
      text: state.sourceText,
      operations: operations,
      registration: registration,
      principal: principal,
      limits: limits,
    );
    if (outcome.failure != null) {
      // A permission denial is the answer of the whole
      // call: it is about who is asking, and the batch did not
      // get far enough to have a candidate.
      return _refused(registration, outcome.failure!,
          issues: outcome.issues.items, candidateText: outcome.candidateText);
    }
    if (outcome.hasPreservationConflict) {
      return _refused(
        registration,
        AisetFailure(
          AisetErrorCode.commentPreservationConflict,
          'The candidate cannot preserve the comments of the source it edits',
          detail: 'pointer ${outcome.preservationConflict}',
        ),
        issues: outcome.issues.items,
        candidateText: outcome.candidateText,
      );
    }
    final candidateText = outcome.candidateText;
    final candidateDocument = outcome.candidateDocument;
    if (candidateText == null || candidateDocument == null) {
      if (dryRun) {
        return AisetWriteResult(
          document: documentId,
          stored: false,
          revision: state.sourceRevision,
          descriptorRevision: state.descriptorRevision,
          activeRevision: state.activeRevision,
          applicationState: null,
          changedPaths: const [],
          issues: outcome.issues.items,
          layerRevision: layers,
          resolverRevision: resolver,
          registryRevision: registry,
        );
      }
      return _refused(registration,
          AisetFailure(AisetErrorCode.validationError, 'Staged operations are invalid',
              issues: outcome.issues.errors),
          issues: outcome.issues.items);
    }
    if (outcome.hasErrors) {
      if (dryRun) {
        // A dry run reports rather than refuses: the caller asked
        // what would happen, and an invalid batch is the answer
        // to that question. It stores nothing and
        // notifies nobody either way.
        return AisetWriteResult(
          document: documentId,
          stored: false,
          revision: state.sourceRevision,
          descriptorRevision: state.descriptorRevision,
          activeRevision: state.activeRevision,
          applicationState: null,
          changedPaths: const [],
          issues: outcome.issues.items,
          candidateText: candidateText,
          layerRevision: layers,
          resolverRevision: resolver,
          registryRevision: registry,
        );
      }
      return _refused(
          registration,
          AisetFailure(AisetErrorCode.validationError, 'Staged operations are invalid',
              issues: outcome.issues.errors),
          issues: outcome.issues.items,
          candidateText: candidateText);
    }
    final changedPaths =
        batchChangedPaths(state.document, candidateDocument, operations);

    if (dryRun) {
      // The pipeline stops here: no probe, no
      // recheck, no commit, no apply, no audit, no notification, and
      // the stored source is byte-identical.
      //
      // A dry run reports no changed paths: nothing changed.
      // The batch paths are computed only when a write is about
      // to commit, which is exactly what the executed
      // baseline does (its `OperationsResult` leaves `changed_paths` empty on
      // the `dry_run` early return). `SPEC.md` amendment 3
      // write rule 7 fixes the byte-identity, and no amendment requires a
      // dry run to advertise the paths it did not touch.
      return AisetWriteResult(
        document: documentId,
        stored: false,
        revision: state.sourceRevision,
        descriptorRevision: state.descriptorRevision,
        activeRevision: state.activeRevision,
        applicationState: null,
        changedPaths: const [],
        issues: outcome.issues.items,
        candidateText: candidateText,
        layerRevision: layers,
        resolverRevision: resolver,
        registryRevision: registry,
      );
    }

    // -- probe -------------------------------------------------------------
    final probeFailure = await _runProbes(state, candidateText, changedPaths);
    if (probeFailure != null) {
      return _refused(registration, probeFailure,
          issues: outcome.issues.items, candidateText: candidateText);
    }

    // -- the write, serialized inside this service -------------------
    return _awaitWrite(() => _commit(
          registration: registration,
          state: state,
          expected: expected,
          candidateText: candidateText,
          changedPaths: changedPaths,
          issues: outcome.issues.items,
          principal: principal,
          captured: (layers: layers, resolver: resolver, registry: registry),
        ));
  }

  /// Convenience for the single-pointer write the editor's
  /// field commit performs: one `set` operation through the same
  /// pipeline, with the same guarantees.
  Future<AisetWriteResult> setValue(
    String documentId,
    String pointer,
    String valueText, {
    required RevisionPair expected,
    required Principal principal,
    bool dryRun = false,
  }) =>
      applyOperations(
        documentId,
        [AisetOperation(kind: AisetOperationKind.set, path: pointer, valueText: valueText)],
        expected: expected,
        principal: principal,
        dryRun: dryRun,
      );

  /// Validates one submitted value at [pointer] without
  /// building or writing a candidate (`SPEC.md` amendments 8 and 14).
  Future<AisetValidationResult> validateValue(
    String documentId,
    String pointer,
    String valueText, {
    required RevisionPair expected,
    required Principal principal,
  }) async {
    final registration = registrationOf(documentId);
    if (!principal.has(AisetPermission.validate)) {
      throw AisetFailure(
          AisetErrorCode.forbidden, 'Principal lacks the ${AisetPermission.validate} permission');
    }
    final state = _states[documentId] ?? await _reload(documentId);
    final failure = _checkPair(state, expected);
    if (failure != null) {
      return AisetValidationResult(
        document: documentId,
        valid: false,
        preservable: failure.code != AisetErrorCode.commentPreservationConflict,
        issues: failure.issues,
        revision: state.sourceRevision,
        descriptorRevision: state.descriptorRevision,
      );
    }
    final outcome = buildCandidate(
      text: state.sourceText,
      operations: [
        AisetOperation(kind: AisetOperationKind.set, path: pointer, valueText: valueText),
      ],
      registration: registration,
      principal: principal,
      limits: limits,
    );
    final issues = outcome.issues;
    issues.locateWith((path) => locatePointer(
        outcome.candidateDocument ?? state.document, path));
    return AisetValidationResult(
      document: documentId,
      valid: !issues.hasErrors && !outcome.hasPreservationConflict,
      preservable: !outcome.hasPreservationConflict,
      issues: issues.items,
      revision: state.sourceRevision,
      descriptorRevision: state.descriptorRevision,
      candidateText: outcome.candidateText,
    );
  }

  /// Validates a whole candidate source against the
  /// document's descriptor, writing nothing (`SPEC.md` amendments 8
  /// and 12: an import or a Save As preview).
  Future<AisetValidationResult> validateDocumentSource(
    String documentId,
    String source, {
    required Principal principal,
  }) async {
    final registration = registrationOf(documentId);
    _require(principal, AisetPermission.validate);
    final state = _states[documentId] ?? await _reload(documentId);
    Json5Document candidate;
    try {
      candidate = Json5Document(source, origin: documentId);
    } on Json5SourceException catch (error) {
      return AisetValidationResult(
        document: documentId,
        valid: false,
        preservable: true,
        issues: [AisetIssue(rule: 'parse', path: '', message: error.message)],
        revision: state.sourceRevision,
        descriptorRevision: state.descriptorRevision,
      );
    }
    final stored = candidate.storedValue();
    final issues = AisetIssueList();
    issues.addAll(_resolveAndValidate(stored, registration, limits));
    // An external candidate is stored verbatim, so it is
    // preservable by definition: the preservation contract binds
    // an edit to a source, and this call changes
    // nothing. It is reported true, not assumed true by an
    // empty comparison.
    const preservable = true;
    return AisetValidationResult(
      document: documentId,
      valid: !issues.hasErrors,
      preservable: preservable,
      issues: issues.items,
      revision: state.sourceRevision,
      descriptorRevision: state.descriptorRevision,
      candidateText: source,
    );
  }

  /// The host's confirmation that it applied a reload or restart
  /// (`SPEC.md` amendment 8: "the host calls a public confirmation of a
  /// successful reload or restart, after which the active snapshot is
  /// updated").
  ///
  /// Until then [AisetSnapshot.activeRevision] lags behind the stored
  /// revision and the editor shows pending application separately from
  /// validation errors. Confirming an unknown or stale revision is
  /// `REVISION_CONFLICT`: a host cannot mark a document active that
  /// was not the one it read.
  Future<AisetSnapshot> confirmApplied(
    String documentId,
    String revision, {
    required Principal principal,
  }) async {
    final registration = registrationOf(documentId);
    final state = _states[documentId] ?? await _reload(documentId);
    if (state.sourceRevision != revision) {
      throw AisetFailure(
        AisetErrorCode.revisionConflict,
        'The confirmed revision is not the stored one',
        detail: 'stored=${state.sourceRevision}',
      );
    }
    _activeTrees[documentId] = state.effectiveTree;
    final active = AisetSnapshot(
      documentId: state.documentId,
      sourceText: state.sourceText,
      storedTree: state.storedTree,
      effectiveTree: state.effectiveTree,
      activeTree: state.effectiveTree,
      provenance: state.provenance,
      sourceRevision: state.sourceRevision,
      descriptorRevision: state.descriptorRevision,
      activeRevision: revision,
      layersRevision: state.layersRevision,
      resolverRevision: state.resolverRevision,
      registryRevision: state.registryRevision,
      issues: state.issues,
      loadedFrom: state.loadedFrom,
      invalidOnDisk: state.invalidOnDisk,
      invalidReason: state.invalidReason,
      document: state.document,
    );
    _states[documentId] = active;
    _audit('application_confirmed', {
      'document': documentId,
      'revision': revision,
      'mode': registration.storage.capabilities.mode.label,
    });
    return active;
  }

  // -- pipeline internals ---------------------------------------------------------

  /// The `REVISION_REQUIRED` / `REVISION_CONFLICT`
  /// precondition of a revision-bound operation (`SPEC.md` amendment 8).
  AisetFailure? _checkPair(AisetSnapshot state, RevisionPair expected) {
    if (!expected.isComplete) {
      return AisetFailure(
        AisetErrorCode.revisionRequired,
        'The expected source and descriptor revisions are required',
      );
    }
    if (expected.source != state.sourceRevision) {
      return AisetFailure(
        AisetErrorCode.revisionConflict,
        'Stale source revision; re-read the document before saving',
        detail: 'current=${state.sourceRevision} client=${expected.source}',
      );
    }
    if (expected.descriptor != state.descriptorRevision) {
      return AisetFailure(
        AisetErrorCode.revisionConflict,
        'Stale descriptor revision; reload the descriptor before saving',
        detail: 'current=${state.descriptorRevision} client=${expected.descriptor}',
      );
    }
    return null;
  }

  /// Runs the pre-commit probes in registration order
  /// under [callbackTimeout].
  ///
  /// A probe runs before the write and outside the lock; a long
  /// asynchronous probe therefore never holds a storage
  /// lock (`SPEC.md` amendment 9). The first veto or failure
  /// ends the run.
  Future<AisetFailure?> _runProbes(
      AisetSnapshot state, String candidateText, List<String> changedPaths) async {
    if (_probes.isEmpty) return null;
    final Object? after;
    try {
      after = Json5Document(candidateText, origin: state.documentId).storedValue();
    } on Json5SourceException {
      return null;
    }
    final before = immutableTree(state.storedTree);
    final runner = CallbackRunner(timeout: callbackTimeout, audit: _audit);
    for (final probe in List<ProbeCallback>.of(_probes)) {
      final result = await runner.call<Object?>((cancel) => probe(
            before,
            immutableTree(after),
            List<String>.unmodifiable(changedPaths),
          ), name: 'probe_changes');
      switch (result.outcome) {
        case CallbackOutcome.timedOut:
          return AisetFailure(
            AisetErrorCode.callbackTimeout,
            'A pre-commit probe exceeded its bound',
            detail: '${callbackTimeout?.inMilliseconds ?? 0}ms',
          );
        case CallbackOutcome.failed:
          final error = result.error;
          if (error is AisetFailure) return error;
          return AisetFailure(
            AisetErrorCode.internalError,
            'A pre-commit probe failed',
            detail: '${error.runtimeType}',
          );
        case CallbackOutcome.completed:
        case CallbackOutcome.cancelled:
          final rejection = result.rejection;
          if (rejection != null) {
            return AisetFailure(AisetErrorCode.validationError, rejection.message,
                issues: rejection.issues);
          }
          if (result.outcome == CallbackOutcome.cancelled) {
            return AisetFailure(
                AisetErrorCode.callbackTimeout, 'A pre-commit probe was cancelled before the commit');
          }
      }
    }
    return null;
  }

  /// Serializes this service's commits.
  Future<T> _awaitWrite<T>(Future<T> Function() write) {
    final next = _writeGate.then((_) => write());
    _writeGate = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// recheck → commit → apply → audit.
  ///
  /// The store is re-read and the exact candidate re-validated
  /// while the write gate is held, so a candidate prepared before a
  /// long probe is checked against the state that is about to be
  /// replaced. The internal layer, resolver and
  /// registry revisions captured at prepare time are verified here too.
  Future<AisetWriteResult> _commit({
    required AisetDocumentRegistration registration,
    required AisetSnapshot state,
    required RevisionPair expected,
    required String candidateText,
    required List<String> changedPaths,
    required List<AisetIssue> issues,
    required Principal principal,
    required ({String layers, String resolver, String registry}) captured,
  }) async {
    final documentId = registration.documentId;
    final storage = registration.storage;
    // -- recheck ---------------------------------------------------------------
    final current = await storage.read();
    if (current.revision != state.sourceRevision) {
      _audit('revision_conflict_on_commit', {
        'document': documentId,
        'client': state.sourceRevision,
        'stored': current.revision,
      });
      return _refused(
        registration,
        AisetFailure(
          AisetErrorCode.revisionConflict,
          'The document changed while the candidate was prepared; re-read before saving',
          detail: 'stored=${current.revision} client=${state.sourceRevision}',
        ),
        issues: issues,
        candidateText: candidateText,
      );
    }
    final pairFailure = _checkPair(state, expected);
    if (pairFailure != null) {
      return _refused(registration, pairFailure, issues: issues, candidateText: candidateText);
    }
    if (captured.layers != registration.layersRevision ||
        captured.resolver != computeResolverRevision(registration.resolver) ||
        captured.registry != registryRevisionOf(registration)) {
      return _refused(
        registration,
        AisetFailure(
          AisetErrorCode.revisionConflict,
          'A layer, resolver or registry input changed while the candidate was prepared',
          detail: 'recheck failed',
        ),
        issues: issues,
        candidateText: candidateText,
      );
    }
    if (!storage.capabilities.conditionalWrite &&
        !registration.allowSingleWriterStorage) {
      return _refused(
        registration,
        AisetFailure(
          AisetErrorCode.unsupportedCapability,
          'The selected storage adapter provides no atomic conditional write, so a '
              'concurrent write cannot be refused safely',
          detail: storage.capabilities.note,
        ),
        issues: issues,
        candidateText: candidateText,
      );
    }
    // The exact candidate is re-validated here, so a
    // candidate that was prepared before a long probe is
    // checked again against the state that is about to be replaced
    // (`SPEC.md` amendment 8: recheck snapshot, then commit).
    final revalidated = _revalidateText(registration, candidateText, storage);
    if (revalidated != null) {
      return _refused(registration, revalidated, issues: issues, candidateText: candidateText);
    }
    // -- commit ----------------------------------------------------------------
    final commit = await storage.compareAndSwap(
        expectedRevision: current.revision, sourceText: candidateText);
    if (!commit.isCommitted) {
      if (commit.status == AisetCommitStatus.uncertain) {
        // The state is re-read rather than the write
        // repeated blindly (`SPEC.md` amendment 8).
        _audit('commit_uncertain', {'document': documentId, 'stored': current.revision});
        return _refused(
          registration,
          AisetFailure(
            AisetErrorCode.storageError,
            'The outcome of the write could not be established; the document state is '
                're-read instead of the write being repeated',
            detail: commit.detail,
          ),
          issues: issues,
          candidateText: candidateText,
          commit: commit.report,
        );
      }
      return _refused(
        registration,
        AisetFailure(
          commit.status == AisetCommitStatus.revisionConflict
              ? AisetErrorCode.revisionConflict
              : AisetErrorCode.storageError,
          commit.status == AisetCommitStatus.revisionConflict
              ? 'The document changed while the candidate was prepared; re-read before saving'
              : 'The document could not be persisted',
          detail: commit.detail,
        ),
        issues: issues,
        candidateText: candidateText,
        commit: commit.report,
      );
    }
    final newRevision = commit.revision ?? sourceRevisionOfText(candidateText);
    var newState = await buildSnapshot(
      registration: registration,
      sourceText: candidateText,
      sourceRevision: newRevision,
      activeTree: _activeTrees[documentId],
      activeRevision: state.activeRevision,
      loadedFrom: storage.capabilities.mode.label,
      limits: limits,
      registryRevision: captured.registry,
    );
    _states[documentId] = newState;

    // -- apply -----------------------------------------------------------------
    final policy = _requiredPolicy(registration, changedPaths);
    var application = switch (policy) {
      ApplyPolicy.live => ApplicationState.applied,
      ApplyPolicy.reload => ApplicationState.reloadRequired,
      ApplyPolicy.restart => ApplicationState.restartRequired,
    };
    if (_application.isNotEmpty && (policy == ApplyPolicy.live || policy == ApplyPolicy.reload)) {
      final runner = CallbackRunner(timeout: callbackTimeout, audit: _audit);
      final previous = immutableTree(state.effectiveTree);
      final next = immutableTree(newState.effectiveTree);
      for (final callback in List<ApplicationCallback>.of(_application)) {
        final result = await runner.call<void>(
            (cancel) => callback(previous, next, changedPaths),
            name: 'application');
        if (result.outcome != CallbackOutcome.completed) {
          application = ApplicationState.applyFailed;
          _audit('apply_failed', {
            'document': documentId,
            'outcome': result.outcome.name,
            if (result.error != null) 'error': '${result.error.runtimeType}',
          });
          break;
        }
      }
    }
    // `live` and a host confirmation are what moves
    // the active revision; a reload, restart or failed
    // apply leaves the application running on the revision it
    // actually holds (`SPEC.md` amendment 8, APP-01).
    var activeRevision = newState.activeRevision;
    if (application == ApplicationState.applied) {
      activeRevision = newRevision;
      _activeTrees[documentId] = newState.effectiveTree;
      newState = newState.withActive(
          newActiveRevision: newRevision, newActiveTree: newState.effectiveTree);
      _states[documentId] = newState;
    }

    // -- audit and subscriptions ----------------------------------------------
    final event = ChangeEvent(
      document: documentId,
      changedPaths: changedPaths,
      previousRevision: state.sourceRevision,
      revision: newRevision,
      applicationState: application.label,
      activeRevision: activeRevision,
    );
    _audit('operations', {
      'document': documentId,
      'operations': [for (final operation in changedPaths) operation],
      'revision': newRevision,
      'application': application.label,
      'principal': principal.id,
    });
    await _notify(state, newState, event, issues);

    return AisetWriteResult(
      document: documentId,
      stored: true,
      revision: newRevision,
      descriptorRevision: registration.descriptor.revision,
      activeRevision: activeRevision,
      applicationState: application,
      changedPaths: changedPaths,
      issues: issues,
      candidateText: candidateText,
      commit: commit.report ??
          CommitReport(
              committed: true, revision: newRevision, document: documentId),
      layerRevision: captured.layers,
      resolverRevision: captured.resolver,
      registryRevision: captured.registry,
    );
  }

  /// Re-parses, re-resolves and re-validates the exact bytes that are
  /// about to be stored, while the write gate is held.
  ///
  /// This is the amendment's "recheck snapshot" applied to the
  /// candidate itself: a descriptor, layer or resolver that
  /// changed during a long probe invalidates the prepared candidate
  /// here rather than after the store accepted it. Returns the refusal,
  /// or `null` when the candidate is still valid.
  AisetFailure? _revalidateText(
      AisetDocumentRegistration registration, String candidateText, AisetStorage storage) {
    final Json5Document candidate;
    try {
      candidate = Json5Document(candidateText, origin: registration.documentId);
    } on Json5SourceException catch (error) {
      return AisetFailure(AisetErrorCode.parseError, error.message,
          issues: [AisetIssue(rule: 'parse', path: '', message: error.message)]);
    }
    final issues = AisetIssueList();
    issues.addAll(_resolveAndValidate(candidate.storedValue(), registration, limits));
    if (issues.hasErrors) {
      return AisetFailure(AisetErrorCode.validationError, 'Candidate configuration is invalid',
          issues: issues.errors);
    }
    return null;
  }

  /// The strictest `apply` policy among the changed paths.
  ///
  /// A node without a declared policy means `restart`, so an
  /// unmarked value never pretends to be live (`SPEC.md`
  /// amendment 8). A path the descriptor does not govern contributes
  /// nothing: an undeclared value is not something the host can
  /// apply at all.
  ApplyPolicy _requiredPolicy(AisetDocumentRegistration registration, List<String> changedPaths) {
    final policies = <ApplyPolicy>[];
    for (final changed in changedPaths) {
      final node = registration.descriptor.nodeAt(changed);
      if (node == null) continue;
      final policy = ApplyPolicy.tryParse(node.apply);
      if (policy != null) policies.add(policy);
    }
    if (policies.isEmpty) return ApplyPolicy.restart;
    return ApplyPolicy.strictestOf(policies);
  }

  /// Delivers the subscriptions and the post-commit observers, after
  /// the lock and the commit.
  ///
  /// A listener that fails is reported to the audit
  /// sink and never cancels the committed result
  /// (`SPEC.md` amendment 9). A subscription whose
  /// principal may not read a secret subtree is not delivered an event about
  /// that subtree at all.
  Future<void> _notify(AisetSnapshot previous, AisetSnapshot next, ChangeEvent event,
      List<AisetIssue> issues) async {
    final runner = CallbackRunner(timeout: callbackTimeout, audit: _audit);
    for (final subscription in _subscriptions.active) {
      if (subscription.document != event.document) continue;
      final matched = subscription.matches(event.changedPaths);
      if (matched.isEmpty) continue;
      final allowed = subscription.permissionFilter ?? (_) => true;
      if (matched.any((path) => !allowed(path))) {
        _audit('subscription_suppressed', {
          'document': event.document,
          'subscription': subscription.id,
          'reason': 'secret',
        });
        continue;
      }
      await runner.guarded((cancel) => subscription.listener(event), name: 'subscription');
    }
    if (_afterSave.isEmpty) return;
    final before = immutableTree(previous.storedTree);
    final after = immutableTree(next.storedTree);
    for (final callback in List<AfterSaveCallback>.of(_afterSave)) {
      await runner.guarded(
          (cancel) => callback(before, after, event.toMap()), name: 'after_save');
    }
  }

  AisetWriteResult _refused(
    AisetDocumentRegistration registration,
    AisetFailure failure, {
    List<AisetIssue> issues = const [],
    String? candidateText,
    CommitReport? commit,
  }) {
    final state = _states[registration.documentId];
    _audit('rejected', {
      'document': registration.documentId,
      'code': failure.code,
      if (failure.detail != null) 'detail': failure.detail,
    });
    return AisetWriteResult(
      document: registration.documentId,
      stored: false,
      revision: state?.sourceRevision ?? '',
      descriptorRevision: registration.descriptor.revision,
      activeRevision: state?.activeRevision ?? '',
      applicationState: null,
      changedPaths: const [],
      issues: issues,
      candidateText: candidateText,
      commit: commit,
      failure: failure,
    );
  }

  void _require(Principal principal, String permission) {
    if (!principal.has(permission)) {
      throw AisetFailure(
          AisetErrorCode.forbidden, 'Principal \'${principal.id}\' lacks $permission');
    }
  }

  void _audit(String name, Map<String, Object?> payload) {
    _auditSink?.call(name, Map<String, Object?>.unmodifiable(payload));
  }
}
