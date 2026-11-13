/// Pure-Dart core for Aiset.
///
/// Currently provides the lossless JSON5/template concrete syntax tree with
/// byte-exact source round-trip, dual UTF-8 byte and UTF-16 code-unit offsets
/// and first-class comment nodes with baseline ownership semantics, plus the
/// source-preserving operations `find`, `applySet`, `applyAdd`, `applyRemove`,
/// `applyMove` and `applyRename`, plus the descriptor grammar: `validateDescriptor`,
/// `compileDescriptor`, `DescriptorNode`, `nodeAt`, `descriptorRevision` and the
/// two-form `description`/`title` text of SPEC_.md amendment 41, the
/// resolver with injected layers and provenance, and the value
/// validator with the resource limits and the accepted regex dialect of
/// `docs/grammars.md`, the base-or-update `merge`, the three revisions with
/// their internal layer/resolver/registry companions, and the single write
/// pipeline: `AisetService` with its authorization, revision pair, atomic
/// operation batches, dry run, pre-commit probes, post-commit observers,
/// application handler and subscriptions.
///
/// The concrete storage adapters and bootstrap source selection are added by
/// slice 2E; the pipeline works against the [AisetStorage] port and the
/// [AisetMemoryStorage] test store.
library;

export 'src/descriptor/descriptor.dart'
    show
        CompiledDescriptor,
        DescriptorDiagnostic,
        DescriptorException,
        DescriptorFragment,
        DescriptorGrammar,
        DescriptorIssue,
        DescriptorNode,
        DescriptorSeverity,
        DescriptorText,
        DescriptorTranslator,
        LocalizedText,
        PlainText,
        PropertyType,
        codePointLength,
        compileDescriptor,
        defaultDescriptorLanguage,
        descriptorRevision,
        descriptorVersion,
        lookupTags,
        matchesPropertyType,
        normalizeLanguageTag,
        normalizeLanguageTagOrNull,
        readDescriptorText,
        resolveDescription,
        sha256Hex,
        validateDescriptor;

export 'src/resolver/resolver.dart'
    show
        Provenance,
        ProvenanceKind,
        ResolutionIssue,
        ResolutionResult,
        ResolutionSeverity,
        Resolver,
        VariableLookup,
        VariableSource,
        buildEffective,
        effectiveAt,
        isMissing,
        resolveText,
        resolveValue,
        resolverMissing;

export 'src/validator/validator.dart'
    show
        Limits,
        PatternCheck,
        PatternRejection,
        ValidationIssue,
        ValidationOutcome,
        ValidationSeverity,
        checkLimits,
        checkPatternDialect,
        validateDocument,
        validateValue;

export 'src/json5/json5.dart'
    show
        ArrayNode,
        BooleanNode,
        CommentKind,
        CommentNode,
        CommentRole,
        CstNode,
        ItemNode,
        Json5CommentConflictException,
        Json5Document,
        Json5ParseException,
        Json5PathException,
        Json5SourceException,
        KeyNode,
        MemberNode,
        NullNode,
        NumberNode,
        ObjectNode,
        OffsetMap,
        SourceSpan,
        StringNode,
        TemplateNode,
        TemplateRef,
        TokenNode,
        ValueNode,
        WhitespaceNode,
        parse;

export 'src/errors/errors.dart'
    show AisetErrorCode, AisetFailure, AisetIssue, AisetIssueList, AisetSeverity;

export 'src/merge/merge.dart'
    show
        MergePreference,
        MergePreferenceError,
        merge,
        mergeLabeled,
        mergeAsViews,
        treeUnchanged,
        immutableTree,
        mutableCopy,
        sameTreeValue;

export 'src/revision/revision.dart'
    show
        MountLayer,
        RevisionPair,
        RevisionSnapshot,
        computeLayerRevision,
        computeRegistryRevision,
        computeResolverRevision,
        revisionOfCanonical,
        sourceRevisionOfBytes,
        sourceRevisionOfText;

export 'src/subscription/subscription.dart'
    show
        AfterSaveCallback,
        ApplicationCallback,
        AuditSink,
        CallbackCancellation,
        CallbackOutcome,
        CallbackResult,
        CallbackRunner,
        ChangeEvent,
        ChangeListener,
        ProbeCallback,
        Rejection,
        SubscriptionHandle,
        SubscriptionRegistry;

export 'src/pipeline/pipeline.dart'
    show
        AisetCommitResult,
        AisetCommitStatus,
        AisetDocumentRegistration,
        AisetMemoryStorage,
        AisetOperation,
        AisetOperationKind,
        AisetPermission,
        AisetService,
        AisetSnapshot,
        AisetStorage,
        AisetStorageCapabilities,
        AisetStoredDocument,
        AisetValidationResult,
        AisetValueResult,
        AisetVeto,
        AisetWriteResult,
        ApplyPolicy,
        ApplicationState,
        CandidateOutcome,
        CommitReport,
        MountPointer,
        PipelineStage,
        Principal,
        StorageMode,
        ValidationAuthority,
        addressesNode,
        applyMountLayers,
        batchChangedPaths,
        buildCandidate,
        buildSnapshot,
        changedPathsFor,
        commentsPreserved,
        keyMatchesPattern,
        locatePointer,
        mountIdentityFields,
        mountToPointer,
        parentPointerText,
        pointerOfTokens,
        pointerPrefixes,
        pathsSafely,
        sourceSliceAt,
        splitPointer,
        submittedPaths,
        subtreeHasSecret,
        unescapePointerToken,
        validateResolved;
