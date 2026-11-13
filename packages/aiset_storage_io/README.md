# aiset_storage_io

Native-file storage adapter for the Aiset pipeline
(`SPEC.md` amendments 10 and 11): the `local` /
`native_file` mode. Pure Dart with `dart:io` — no Flutter
import — so it serves CLI tools and mobile/desktop Flutter
apps alike as a plain Dart dependency.

One adapter is one registered document file. It reads the
verbatim source text with its revision
(`sha256:` over the stored bytes, BOM included), and its
compare-and-swap re-checks that revision inside a cross-process
sidecar lock and replaces the file atomically
(temp file + same-directory rename). It keeps the baseline's
bounded `.back` backup chain — default depth 5, one rotation
per editing session — reads the newest valid backup back as the
last known good, and preserves rejected external bytes as
timestamped conflicted copies. Capability flags state exactly
what it guarantees: no change notifications (external edits are
adopted by an explicit reread), no cross-isolate concurrency claim
(one adapter instance per document inside one process).

## Usage

```dart
import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';

final storage = AisetNativeFileStorage('/path/to/config.json5');
final service = AisetService();
service.register(AisetDocumentRegistration(
  documentId: 'app',
  storage: storage,
  descriptorSource: descriptorText,
));

final snapshot = await service.load('app', principal: Principal.demo());
final result = await service.setValue(
  'app', '/server/port', '8080',
  expected: snapshot.revisionPair,
  principal: Principal.demo(),
);
// result.stored == true only after the atomic replace landed.
```

A load/reread boundary re-arms the session backup:

```dart
final fresh = await service.reread('app', principal: principal);
storage.beginEditingSession(); // the next committed edit takes a .back slot
```

The last-known-good fallback is a separate call and reads
the chain only — it never overwrites an invalid current source;
`restoreLastValidated` and `restoreBackup` are the explicit host
commands. See `lib/src/backup_chain.dart`.
