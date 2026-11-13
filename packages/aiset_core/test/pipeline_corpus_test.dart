import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'corpus_expectations.dart';

/// Replays every generated pipeline case against the Dart service.
///
/// * `pipeline_operations` — the batches that store: the six operation
///   kinds, sequential visibility inside one batch, create-then-fill, the
///   reported changed paths and the application state.
/// * `pipeline_dry_run` — a valid and an invalid dry run, each pinning that
///   the stored source and the service's own view of it stay
///   byte-identical (`SPEC.md` amendment 3 write rule 7).
/// * `pipeline_rejections` — each documented rejection reason with its stable
///   code (`SPEC.md` amendments 8 and 26).
/// * `pipeline_revision_pair` — the revision-pair CAS contract between two
///   independent writers over one document (`SPEC.md` amendment 8, REV-01).
/// * `pipeline_views` — the stored, effective and active views of a
///   registered document with their provenance and the six leaf states.
/// * `pipeline_callbacks` — the pre-commit probe, the post-commit observer,
///   the application handler and the subscriptions, with their bounds
///   (`SPEC.md` amendment 9).
///
/// The replay rebuilds the payload the driver recorded and compares it field
/// by field, so a divergence case asserts its corrected expectation through
/// the same path an ordinary case asserts the baseline's
/// (`SPEC_.md` amendment 38). Issues are compared order-insensitively: which
/// rules fire at which pointer is the contract, the order the walk
/// produced them in is not.
void main() {
  final corpus = CompatCorpus.load();

  group('pipeline corpus integrity', () {
    test('the pipeline areas are present and counted in BASELINE', () {
      final counts = corpus.baseline()['counts']! as Map<String, Object?>;
      for (final area in const [
        'pipeline_operations',
        'pipeline_dry_run',
        'pipeline_rejections',
        'pipeline_revision_pair',
        'pipeline_views',
        'pipeline_callbacks',
      ]) {
        expect(counts[area], equals(corpus.area(area).length), reason: area);
        expect(counts[area]! as int, greaterThan(0), reason: area);
      }
    });

    test('the pipeline corpus covers OPS-01, REV-01 and APP-01', () {
      final stored = corpus.area('pipeline_operations');
      bool any(List<CompatCase> cases, String tag) =>
          cases.any((c) => c.classes.contains(tag));
      for (final kind in const ['set', 'add', 'remove', 'move', 'rename', 'drop']) {
        expect(any(stored, kind), isTrue, reason: 'no stored $kind case');
      }
      expect(any(stored, 'create-then-fill'), isTrue,
          reason: 'no create-container-then-fill batch (OPS-01)');
      expect(any(stored, 'sequential'), isTrue,
          reason: 'no case proving a later operation sees an earlier one');
      expect(any(stored, 'append'), isTrue, reason: 'no append case');
      expect(any(stored, 'placeholder'), isTrue, reason: 'no placeholder case');
      expect(any(stored, 'preserve'), isTrue, reason: 'no comment-preservation case');
      for (final policy in const ['live', 'reload', 'restart', 'strictest']) {
        expect(any(stored, policy), isTrue, reason: 'no $policy application case');
      }
      expect(any(stored, 'changed-paths'), isTrue, reason: 'no changed-paths case');

      final dry = corpus.area('pipeline_dry_run');
      expect(dry.any((c) => c.expected['valid'] == true), isTrue,
          reason: 'no accepting dry-run case');
      expect(dry.any((c) => c.expected['valid'] == false), isTrue,
          reason: 'no rejecting dry-run case');

      final rejected = corpus.area('pipeline_rejections');
      final codes = {
        for (final c in rejected)
          if (c.expected['result'] == 'rejected') c.expected['errorCode'],
      };
      for (final code in const [
        'REVISION_REQUIRED',
        'REVISION_CONFLICT',
        'FORBIDDEN',
        'SECRET_ACCESS_DENIED',
        'VALIDATION_ERROR',
        'BAD_REQUEST',
      ]) {
        expect(codes, contains(code), reason: 'no case for the $code rejection');
      }
      expect(any(rejected, 'limits'), isTrue, reason: 'no resource-limit rejection');
      expect(
          any(rejected, 'required') && any(rejected, 'read-only') && any(rejected, 'const'),
          isTrue,
          reason: 'no descriptor-protection rejection');

      final cas = corpus.area('pipeline_revision_pair');
      expect(cas.any((c) => c.classes.contains('accept')), isTrue,
          reason: 'no accepted CAS case');
      expect(
          cas.where((c) => c.classes.contains('rejection')).length,
          greaterThanOrEqualTo(3),
          reason: 'REV-01 needs the absent, stale-source and '
              'stale-descriptor refusals');

      // Every rejection and every dry run proves the byte-identity of the
      // stored source and of the service's own session view.
      for (final testCase in [...rejected, ...dry]) {
        final expected = testCase.expected;
        if (expected['result'] == 'setup_error') continue;
        expect(expected['fileUnchanged'], isTrue,
            reason: '${testCase.id}: the baseline changed the stored source');
        expect(expected['stateTextUnchanged'], isTrue,
            reason: '${testCase.id}: the baseline changed its own session state');
      }
    });

    test('the callback corpus covers amendment 9', () {
      final cases = corpus.area('pipeline_callbacks');
      bool any(String tag) => cases.any((c) => c.classes.contains(tag));
      for (final tag in const [
        'probe',
        'veto',
        'timeout',
        'application',
        'after_save',
        'subscription',
        'cancel',
        'secret',
      ]) {
        expect(any(tag), isTrue, reason: 'no $tag callback case');
      }
      // A committed write is never reported as unsaved.
      for (final testCase in cases) {
        if (testCase.expected['stored'] != true) continue;
        expect(testCase.expected['fileText'], isNotNull,
            reason: '${testCase.id}: a stored write must have new bytes');
      }
    });

    test('no stored case leaves the document unparseable', () {
      // An edit must produce a document the engine still reads.
      for (final area in const ['pipeline_operations', 'pipeline_dry_run']) {
        for (final testCase in corpus.area(area)) {
          final fileText = testCase.expected['fileText'];
          if (fileText is! String) continue;
          expect(() => parse(fileText), returnsNormally,
              reason: '${testCase.id}: the stored source no longer parses');
        }
      }
    });

    test('a rejected run never reports stored bytes', () {
      for (final area in const ['pipeline_operations', 'pipeline_dry_run', 'pipeline_rejections']) {
        for (final testCase in corpus.area(area)) {
          final expected = testCase.expected;
          if (expected['result'] != 'rejected') continue;
          expect(expected['stored'], isFalse, reason: testCase.id);
          expect(expected['fileUnchanged'], isTrue, reason: testCase.id);
        }
      }
    });

    test('a snapshot for a principal without the secret read permission '
        'carries no secret path', () async {
      // SEC-01 as a derived invariant rather than a copied tree: every
      // secret-governed pointer the descriptor declares
      // must be absent from the effective tree and from the
      // provenance map the service hands to a principal that may
      // not read secrets. Nothing here re-states an
      // expectation the fixture could drift from; the rule comes from
      // the descriptor and the permission (`SPEC.md` amendments 2, 9
      // and 26).
      for (final testCase in corpus.area('pipeline_views')) {
        final body = testCase.body;
        final principal = _principal(body['principal']! as String);
        if (principal.has(AisetPermission.readSecret)) continue;
        final descriptor = compileDescriptor(body['descriptor']! as String);
        final secretPaths = <String>[];
        void walk(DescriptorNode node, String pointer) {
          if (node.secret) secretPaths.add(pointer);
          for (final entry in (node.children ?? const <String, DescriptorNode>{}).entries) {
            walk(entry.value, '$pointer${pointerOfTokens([entry.key])}');
          }
        }

        walk(descriptor.root, '');
        expect(secretPaths, isNotEmpty,
            reason: '${testCase.id}: the shared document declares no secret, '
                'so this check would be vacuous');
        final storage = AisetMemoryStorage(initialText: body['config']! as String);
        final service = AisetService();
        service.register(AisetDocumentRegistration(
          documentId: 'cfg',
          storage: storage,
          descriptorSource: body['descriptor']! as String,
          resolver: _resolver(body['layers']),
        ));
        final snapshot = await service.load('cfg', principal: principal);
        final visible = <String>[];
        void scan(Object? tree, String pointer) {
          if (secretPaths.contains(pointer)) visible.add(pointer);
          if (tree is Map) {
            for (final entry in tree.entries) {
              scan(entry.value, '$pointer${pointerOfTokens([entry.key! as String])}');
            }
          } else if (tree is List) {
            for (var index = 0; index < tree.length; index++) {
              scan(tree[index], '$pointer/$index');
            }
          }
        }

        scan(snapshot.effectiveTree, '');
        expect(visible, isEmpty,
            reason: '${testCase.id}: the effective tree shows a secret subtree');
        for (final path in secretPaths) {
          expect(snapshot.provenance.containsKey(path), isFalse,
              reason: '${testCase.id}: provenance names the secret path $path');
        }
      }
    });
  });

  group('staged batches', () {
    for (final area in const [
      'pipeline_operations',
      'pipeline_dry_run',
      'pipeline_rejections',
    ]) {
      for (final testCase in corpus.area(area)) {
        test(testCase.id, () async {
          final body = testCase.body;
          final config = body['config']! as String;
          final storage = AisetMemoryStorage(initialText: config);
          final service = AisetService(limits: _limits(body['limits']));
          service.register(AisetDocumentRegistration(
            documentId: 'cfg',
            storage: storage,
            descriptorSource: body['descriptor']! as String,
            resolver: _resolver(body['layers']),
          ));
          final principal = _principal(body['principal']! as String);
          final snapshot = await service.load('cfg', principal: principal);
          final pair = _revisionPair(body['expectedRevisions'] as String?, snapshot);
          final operations = [
            for (final raw in (body['operations']! as List))
              AisetOperation.fromMap(raw! as Map<String, Object?>),
          ];
          final outcome = await service.applyOperations(
            'cfg',
            operations,
            expected: pair,
            principal: principal,
            dryRun: body['dryRun'] == true,
          );
          final session = await service.load('cfg', principal: principal);
          _expectPipelinePayload(
            actual: pipelinePayload(
              outcome: outcome,
              storedText: storage.text,
              config: config,
              sessionText: session.sourceText,
            ),
            expected: testCase.expected,
            id: testCase.id,
          );
        });
      }
    }
  });

  group('revision pair and CAS', () {
    for (final testCase in corpus.area('pipeline_revision_pair')) {
      test(testCase.id, () async {
        final body = testCase.body;
        final config = body['config']! as String;
        final descriptorSource = body['descriptor']! as String;
        final scenario = body['scenario']! as String;
        final principal = Principal.demo();

        // One document, two independent services: the local-mode case
        // amendment 8 names, where the rules apply between two
        // controllers or windows as well.
        final storage = AisetMemoryStorage(initialText: config);
        final first = AisetService()
          ..register(AisetDocumentRegistration(
              documentId: 'cfg', storage: storage, descriptorSource: descriptorSource));
        final second = AisetService()
          ..register(AisetDocumentRegistration(
              documentId: 'cfg', storage: storage, descriptorSource: descriptorSource));
        final pair = (await first.load('cfg', principal: principal)).revisionPair;
        final out = <String, Object?>{};

        String label(AisetWriteResult result) =>
            result.stored ? 'stored' : (result.failure?.code ?? 'reported');

        switch (scenario) {
          case 'fresh_pair':
            out['firstWrite'] = label(await first.setValue('cfg', '/port', '8080',
                expected: pair, principal: principal));
            final fresh = (await second.reread('cfg', principal: principal)).revisionPair;
            out['secondWrite'] = label(await second.setValue('cfg', '/host', '"other"',
                expected: fresh, principal: principal));
          case 'stale_pair':
            out['secondWrite'] = label(await second.setValue('cfg', '/port', '9090',
                expected: pair, principal: principal));
            out['staleWrite'] = label(await first.setValue('cfg', '/port', '7070',
                expected: pair, principal: principal));
          case 'absent':
            out['absentWrite'] = label(await first.setValue('cfg', '/port', '8080',
                expected: const RevisionPair(), principal: principal));
          case 'wrong_descriptor':
            out['wrongDescriptor'] = label(await first.setValue('cfg', '/port', '8080',
                expected:
                    RevisionPair(source: pair.source, descriptor: 'sha256:${'0' * 32}'),
                principal: principal));
          case 'external_writer':
            // A writer outside both services replaces the file: the next
            // commit must be refused and the foreign bytes must survive.
            storage.writeExternally(_externalEdit);
            out['externalWrite'] = 'stored_externally';
            out['staleWrite'] = label(await first.setValue('cfg', '/port', '7070',
                expected: pair, principal: principal));
          default:
            fail('unknown CAS scenario $scenario');
        }
        out['fileText'] = storage.text;
        out['fileRevision'] = sourceRevisionOfText(storage.text!);

        final expected = testCase.expected;
        for (final entry in out.entries) {
          if (!expected.containsKey(entry.key)) continue;
          expect(entry.value, equals(expected[entry.key]),
              reason: '${testCase.id}: ${entry.key} — ${testCase.description}');
        }
      });
    }
  });

  group('read views', () {
    for (final testCase in corpus.area('pipeline_views')) {
      test(testCase.id, () async {
        final body = testCase.body;
        final storage = AisetMemoryStorage(initialText: body['config']! as String);
        final service = AisetService();
        service.register(AisetDocumentRegistration(
          documentId: 'cfg',
          storage: storage,
          descriptorSource: body['descriptor']! as String,
          resolver: _resolver(body['layers']),
        ));
        final principal = _principal(body['principal']! as String);
        final query = body['query']! as Map<String, Object?>;
        final expected = testCase.expected;
        final out = <String, Object?>{};
        if (query['op'] == 'effective') {
          final snapshot = await service.load('cfg', principal: principal);
          out['effective'] = snapshot.effectiveTree;
          out['provenance'] = {
            for (final entry in snapshot.provenance.entries) entry.key: entry.value.toMap(),
          };
          out['revision'] = snapshot.sourceRevision;
          out['descriptorRevision'] = snapshot.descriptorRevision;
          out['invalidOnDisk'] = snapshot.invalidOnDisk;
          // The same rule the driver applied to the baseline: a marker
          // names the secret value, and the probe asks whether the
          // view handed to this principal carries it. `toString` of a
          // Dart map renders nested values, and it never
          // throws on a TemplateRef the way an encoder would.
          final marker = body['secretMarker'] as String?;
          if (marker != null) {
            out['secretVisible'] = snapshot.effectiveTree.toString().contains(marker);
          }
        } else {
          final pointer = query['pointer']! as String;
          try {
            final value = await service.get('cfg', pointer, principal: principal);
            out['exists'] = value.exists;
            out['defaultApplied'] = value.defaultApplied;
            out['effective'] = value.effective;
            final origin = value.provenance;
            final provenanceOf = {
              if (origin != null) pointer: origin.toMap(),
            };
            // The driver records an empty provenance map as
            // `null`, so the replay maps it the same way.
            out['provenance'] = provenanceOf.isEmpty ? null : provenanceOf;
            out['revision'] = value.revision;
            out['descriptorRevision'] = value.descriptorRevision;
          } on AisetFailure catch (failure) {
            out['result'] = 'rejected';
            out['errorCode'] = failure.code;
            // SEC-01: a refusal must not carry the value.
            expect(failure.issues, isEmpty,
                reason: '${testCase.id}: a denial should not quote a value');
          }
        }
        for (final entry in out.entries) {
          if (!expected.containsKey(entry.key)) continue;
          expect(describeMismatch(entry.value, decodeTaggedTree(expected[entry.key])),
              isNull,
              reason: '${testCase.id}: ${entry.key} — ${testCase.description}');
        }
      });
    }
  });

  group('callbacks and subscriptions', () {
    for (final testCase in corpus.area('pipeline_callbacks')) {
      test(testCase.id, () async {
        final body = testCase.body;
        final config = body['config']! as String;
        final storage = AisetMemoryStorage(initialText: config);
        final seen = _CallbackLog();
        final service = AisetService(callbackTimeout: const Duration(milliseconds: 50));
        service.register(AisetDocumentRegistration(
          documentId: 'cfg',
          storage: storage,
          descriptorSource: body['descriptor']! as String,
          resolver: _resolver(body['layers']),
        ));
        final principal = Principal.demo();
        final snapshot = await service.load('cfg', principal: principal);
        final pair = snapshot.revisionPair;
        final scenario = body['scenario']! as String;

        switch (scenario) {
          case 'veto':
            service.onProbeChanges((before, after, paths) {
              seen.probeCalls++;
              seen.probePaths = paths;
              return const Rejection([
                AisetIssue(rule: 'veto', path: '/port', message: 'host says no'),
              ]);
            });
          case 'timeout':
            service.onProbeChanges((before, after, paths) async {
              seen.probeCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 400));
              return null;
            });
          case 'application_fail':
            service.onApplication((previous, current, paths) {
              seen.applicationCalls++;
              throw StateError('host apply failed');
            });
          case 'after_save_fail':
            service.onAfterSave((previous, current, event) {
              seen.afterSaveCalls++;
              throw StateError('observer blew up');
            });
          case 'subscribe_paths':
          case 'unsubscribe':
          case 'secret_event':
            final subscriber = scenario == 'secret_event'
                ? Principal.demo(id: 'r').withoutPermissions(const [AisetPermission.readSecret])
                : principal;
            final handle = service.subscribe(
              'cfg',
              (body['paths']! as List).cast<String>(),
              (event) => seen.events.add(event.toMap()),
              principal: subscriber,
            );
            if (scenario == 'unsubscribe') handle.cancel();
        }

        final outcome = await service.setValue(
          'cfg',
          body['path']! as String,
          body['value']! as String,
          expected: pair,
          principal: principal,
        );
        if (scenario == 'subscribe_paths' && body.containsKey('other')) {
          final fresh = (await service.reread('cfg', principal: principal)).revisionPair;
          final other = await service.setValue(
              'cfg', body['other']! as String, '"o"', expected: fresh, principal: principal);
          out(other: label(other));
        }
        final actual = pipelinePayload(
          outcome: outcome,
          storedText: storage.text,
          config: config,
          sessionText: (await service.load('cfg', principal: principal)).sourceText,
        )
          ..['probeCalls'] = seen.probeCalls
          ..['applicationCalls'] = seen.applicationCalls
          ..['afterSaveCalls'] = seen.afterSaveCalls
          ..['events'] = seen.events;

        final expected = testCase.expected;
        for (final entry in expected.entries) {
          if (!actual.containsKey(entry.key)) continue;
          if (entry.key == 'issues') {
            _expectSameIssues(actual['issues']! as List<Object?>,
                entry.value! as List<Object?>, testCase.id);
            continue;
          }
          if (entry.key == 'events') continue; // Compared explicitly below.
          expect(actual[entry.key], equals(_plain(entry.value)),
              reason: '${testCase.id}: ${entry.key} — ${testCase.description}');
        }
        _expectEvents(seen.events, expected['events'] as List?, testCase.id);
      });
    }
  });
}

// -- the shared document -------------------------------------------------------

/// The bytes an external writer puts in place of the document.
const String _externalEdit = '{ port: 4242, host: "outside" }\n';

/// The recorded result of one host callback.
class _CallbackLog {
  int probeCalls = 0;
  int applicationCalls = 0;
  int afterSaveCalls = 0;
  List<String> probePaths = const [];
  final List<Map<String, Object?>> events = [];
}

void out({String? other}) => other;

// -- payload comparison ---------------------------------------------------

/// The Dart pipeline payload, in the shape the driver recorded the
/// baseline's.
///
/// The keys the baseline alone can know (`ok`, `id`) are
/// absent, and the comparison skips a field either side does not carry.
Map<String, Object?> pipelinePayload({
  required AisetWriteResult outcome,
  required String? storedText,
  required String config,
  required String sessionText,
}) =>
    {
      'result': outcome.stored
          ? 'stored'
          : (outcome.failure == null ? 'reported' : 'rejected'),
      'stored': outcome.stored,
      'valid': outcome.valid,
      'issues': [
        for (final issue in outcome.issues)
          {'rule': issue.rule, 'path': issue.path, 'severity': issue.severity.label},
      ],
      'changedPaths': outcome.changedPaths,
      'fileUnchanged': storedText == config,
      'stateTextUnchanged': sessionText == config,
      if (outcome.stored) 'fileText': storedText,
      if (outcome.stored) 'revision': outcome.revision,
      if (outcome.stored) 'descriptorRevision': outcome.descriptorRevision,
      if (outcome.stored) 'activeRevision': outcome.activeRevision,
      if (outcome.stored)
        'activeMatchesRevision': outcome.activeRevision == outcome.revision,
      if (outcome.stored) 'application': outcome.applicationState?.label,
      if (outcome.failure != null) 'errorCode': outcome.failure!.code,
    };

/// Compares the Dart payload with the recorded expectation field by field.
void _expectPipelinePayload({
  required Map<String, Object?> actual,
  required Map<String, Object?> expected,
  required String id,
}) {
  for (final entry in expected.entries) {
    if (!actual.containsKey(entry.key)) continue;
    if (entry.key == 'issues') {
      _expectSameIssues(actual['issues']! as List<Object?>,
          entry.value! as List<Object?>, id);
      continue;
    }
    expect(actual[entry.key], equals(_plain(entry.value)), reason: '$id: ${entry.key}');
  }
  if (expected['result'] == 'rejected') {
    expect(actual['errorCode'], isNotNull,
        reason: '$id: a rejection must carry a stable code');
  }
}

/// Compares issue lists as multisets of (rule, path, severity).
void _expectSameIssues(List<Object?> actual, List<Object?> expected, String id) {
  expect(actual.length, equals(expected.length),
      reason: '$id: ${_render(actual)} vs ${_render(expected)}');
  final remaining = [...expected];
  for (final issue in actual) {
    final found = (issue! as Map).cast<String, Object?>();
    final match = remaining.indexWhere((candidate) {
      final want = (candidate! as Map).cast<String, Object?>();
      return (!want.containsKey('rule') || want['rule'] == found['rule']) &&
          (!want.containsKey('path') || want['path'] == found['path']) &&
          (!want.containsKey('severity') || want['severity'] == found['severity']);
    });
    if (match < 0) {
      fail('$id: unexpected issue $found; expected ${_render(expected)}');
    }
    remaining.removeAt(match);
  }
  if (remaining.isNotEmpty) {
    fail('$id: missing issues ${_render(remaining)}; got ${_render(actual)}');
  }
}

/// Compares the delivered subscription events as a list, because the
/// delivery order is part of the documented callback order.
void _expectEvents(List<Map<String, Object?>> actual, List<Object?>? expected, String id) {
  if (expected == null) return;
  expect(actual.length, equals(expected.length), reason: '$id: ${_renderEvents(actual)}');
  for (var index = 0; index < expected.length; index++) {
    final want = (expected[index]! as Map).cast<String, Object?>();
    final have = actual[index];
    for (final entry in want.entries) {
      if (!have.containsKey(entry.key)) continue;
      expect(have[entry.key], equals(entry.value),
          reason: '$id: event $index ${entry.key}');
    }
  }
}

String _render(List<Object?> issues) {
  final rendered = issues.map((issue) {
    final map = (issue! as Map).cast<String, Object?>();
    return '${map['rule']}@${map['path']}';
  });
  return '[${rendered.join(', ')}]';
}

String _renderEvents(List<Map<String, Object?>> events) =>
    '[${events.map((e) => '${e['document']}:${(e['changed_paths'] as List?)?.join(",")}').join(', ')}]';

Object? _plain(Object? expected) =>
    expected is Map || expected is List ? decodeTaggedTree(expected) : expected;

// -- fixture plumbing ------------------------------------------------------------

/// The revision pair the case presents.
RevisionPair _revisionPair(String? kind, AisetSnapshot snapshot) {
  switch (kind) {
    case 'absent':
      return const RevisionPair();
    case 'stale_source':
      return RevisionPair(source: 'sha256:${'0' * 32}', descriptor: snapshot.descriptorRevision);
    case 'stale_descriptor':
      return RevisionPair(source: snapshot.sourceRevision, descriptor: 'sha256:${'0' * 32}');
    default:
      return snapshot.revisionPair;
  }
}

Limits _limits(Object? raw) {
  if (raw is! Map) return Limits.defaultProfile;
  final limits = raw.cast<String, Object?>();
  int read(String key, int fallback) => limits[key] == null ? fallback : limits[key]! as int;
  return Limits(
    maxDepth: read('max_depth', Limits.defaultProfile.maxDepth),
    maxCollectionSize:
        read('max_collection_size', Limits.defaultProfile.maxCollectionSize),
    maxStringLength: read('max_string_length', Limits.defaultProfile.maxStringLength),
    maxPatternLength: read('max_pattern_length', Limits.defaultProfile.maxPatternLength),
  );
}

Resolver _resolver(Object? raw) {
  final layers = (raw! as Map).cast<String, Object?>();
  Map<String, String> read(String key) => {
        for (final entry in (layers[key]! as Map).cast<String, Object?>().entries)
          entry.key: entry.value! as String,
      };
  return Resolver(
      overrides: read('overrides'), environment: read('environ'), dotenv: read('dotenv'));
}

Principal _principal(String name) => switch (name) {
      'demo' => Principal.demo(),
      'no_write' => Principal.demo(id: 'n')
          .withoutPermissions(const [AisetPermission.write, AisetPermission.editSecret]),
      'no_secret_edit' =>
        Principal.demo(id: 's').withoutPermissions(const [AisetPermission.editSecret]),
      'no_secret_read' =>
        Principal.demo(id: 'r').withoutPermissions(const [AisetPermission.readSecret]),
      'validate_only' => Principal.demo(id: 'v').withoutPermissions(const [
          AisetPermission.write,
          AisetPermission.editSecret,
          AisetPermission.validate,
        ]),
      _ => throw StateError('unknown principal $name'),
    };

String label(AisetWriteResult result) =>
    result.stored ? 'stored' : (result.failure?.code ?? 'reported');
