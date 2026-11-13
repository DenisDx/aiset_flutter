import 'dart:io';

import 'package:aiset_core/aiset_core.dart';
import 'package:aiset_storage_io/aiset_storage_io.dart';
import 'package:test/test.dart';

import 'test_utils/helpers.dart';

/// The declared capabilities of the native-file adapter,
/// each with the evidence behind it. `SPEC.md` amendment 11: an
/// adapter reports only what it can honor, and a missing
/// capability is never imitated by an empty success.
void main() {
  test('the default profile declares the native-file guarantee set', () {
    final storage = storageIn(Directory.systemTemp.createTempSync('cap'));
    addTearDown(() {
      if (storage.documentPath.isNotEmpty) {
        final dir = File(storage.documentPath).parent;
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });
    final caps = storage.capabilities;
    expect(caps.mode, StorageMode.local, reason: 'SPEC.md 10: local, built-in adapter');
    expect(caps.persistent, isTrue, reason: 'a real file survives the process');
    expect(caps.conditionalWrite, isTrue,
        reason: 'the revision is checked inside the cross-process lock before the '
            'atomic replace; the two-process race test proves one commit per '
            'revision and no interleaving');
    expect(caps.crossContextConcurrency, isFalse,
        reason: 'the OS sidecar lock excludes between PROCESSES and the in-isolate '
            'queue serializes one isolate, but dart:io record locks do '
            'NOT exclude between isolates of one process (verified by probe), so a '
            'multi-isolate app must share one adapter per document; SPEC.md amendment 8 '
            'forbids selling an in-isolate mutex as cross-context safety');
    expect(caps.sourcePreservation, isTrue,
        reason: 'reads and writes go through raw bytes with a strict UTF-8 codec that '
            'keeps the byte order mark; the round-trip tests pin byte identity');
    expect(caps.backup, isTrue, reason: 'the .back chain rotates once per editing session');
    expect(caps.history, isFalse,
        reason: 'the bounded .back chain is not an edit history: no per-change log, '
            'and the adapter does not pretend otherwise');
    expect(caps.loadLkg, isTrue, reason: 'the newest-valid-backup walk answers loadLkg');
    expect(caps.changeNotifications, isFalse,
        reason: 'watching a file for external edits means polling, and SPEC.md 10 '
            'notes a notification is not a lock in any case; external edits are adopted '
            'by the host\'s explicit reread and a concurrent writer is caught by the CAS');
    expect(caps.validationAuthority, ValidationAuthority.none,
        reason: 'the file stores what it is given; the library validates locally, which '
            'SPEC.md 10 is explicit is not server-side protection');
    expect(caps.note, contains('native_file'));
  });

  test('backupDepth 0 honestly drops the backup and LKG promises', () {
    final dir = Directory.systemTemp.createTempSync('cap0');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final storage =
        storageIn(dir, settings: const AisetNativeFileSettings(backupDepth: 0));
    expect(storage.capabilities.backup, isFalse);
    expect(storage.capabilities.loadLkg, isFalse);
    expect(storage.capabilities.persistent, isTrue, reason: 'a file is still durable');
    expect(storage.capabilities.conditionalWrite, isTrue,
        reason: 'the CAS does not depend on the chain');
    expect(storage.backupDepth, 0);
  });
}
