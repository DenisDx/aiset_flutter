/// The write gate of the native-file adapter: an in-isolate
/// serialization queue plus a bounded cross-process
/// sidecar lock (`SPEC.md` amendments 8 and 10).
///
/// Two layers, because `dart:io` file locks are POSIX
/// record locks and carry their two classic quirks, both
/// verified on this SDK by executed probes:
///
/// * they DO exclude across processes — the sidecar lock is what makes
///   the adapter's compare-and-swap real against a second
///   process (proven by the two-process race test);
/// * they do NOT exclude between two opens of the same file
///   inside one process — a second isolate's lock request succeeds
///   immediately while the first holds it, and closing ANY
///   descriptor for the file releases the whole process's locks.
///
/// So: the in-isolate queue serializes critical sections
/// inside one isolate regardless of the OS lock, and the OS
/// sidecar lock carries the cross-process guarantee. Two isolates of one
/// process writing the same document file are therefore
/// NOT mutually excluded by anything an adapter can honestly
/// claim, which is exactly why the adapter declares
/// `crossContextConcurrency: false` while keeping the real, tested
/// `conditionalWrite: true`.
///
/// The sidecar descriptor is opened once per acquisition and closed
/// exactly once, never while another acquisition holds it, so the
/// "close releases every process lock" quirk cannot bite through any path
/// this file takes.
library;

import 'dart:async';
import 'dart:io';

import 'package:aiset_core/aiset_core.dart';

/// A bounded, retrying exclusive lock on a stable sidecar path.
final class AisetSidecarLock {
  /// Creates the gate for one sidecar path. [timeout] bounds the
  /// whole wait for the OS lock; [pollInterval] spaces the retries.
  AisetSidecarLock(
    this.sidecarPath, {
    required this.timeout,
    this.pollInterval = const Duration(milliseconds: 50),
  });

  /// The sidecar file the OS lock is taken on. It is created on
  /// first use and never deleted, exactly like the baseline's
  /// `<document>.lock` sibling.
  final String sidecarPath;

  /// How long to keep retrying the exclusive lock before
  /// giving up with `LOCK_TIMEOUT`.
  final Duration timeout;

  /// The pause between lock attempts.
  final Duration pollInterval;

  /// One queue tail per canonical sidecar path, serializing this
  /// isolate's critical sections. Removed when its
  /// holder is the last in line.
  static final Map<String, Future<void>> _gates = <String, Future<void>>{};

  /// Runs [body] as the only writer of this sidecar in this
  /// process, holding the cross-process OS lock for the
  /// duration.
  ///
  /// Throws [AisetFailure] with `LOCK_TIMEOUT` when the OS lock cannot
  /// be acquired within [timeout], and propagates a
  /// `STORAGE_ERROR` failure when the sidecar itself
  /// cannot be opened (a permission refusal, an uncreatable
  /// parent): a lock that cannot even be attempted is not a timeout.
  Future<T> hold<T>(Future<T> Function() body) async {
    final key = _canonicalSidecarPath();
    // No await between reading the tail and installing ours:
    // one isolate's event loop makes this handoff atomic.
    final waiting = _gates[key] ?? Future<void>.value();
    final done = Completer<void>();
    _gates[key] = done.future;
    // The queue tail is a pure gate; a previous holder's
    // errors are delivered to its own caller, never here.
    await waiting.then<void>((_) {}, onError: (_) {});
    try {
      return await _withFileLock(body);
    } finally {
      done.complete();
      if (identical(_gates[key], done.future)) _gates.remove(key);
    }
  }

  /// The lock loop itself: open, try, on contention close and retry
  /// until [timeout]; then unlock and close exactly this descriptor.
  Future<T> _withFileLock<T>(Future<T> Function() body) async {
    final deadline = Stopwatch()..start();
    while (true) {
      final raf = await _openSidecar();
      var locked = true;
      try {
        await raf.lock();
      } on FileSystemException {
        locked = false;
      }
      if (!locked) {
        // Contention with another process: close our own
        // descriptor (it holds nothing) and retry within the
        // deadline.
        await raf.close();
        if (deadline.elapsed >= timeout) {
          throw AisetFailure(
            AisetErrorCode.lockTimeout,
            'Could not acquire the store lock within ${timeout.inMilliseconds}ms',
          );
        }
        await Future<void>.delayed(pollInterval);
        continue;
      }
      try {
        return await body();
      } finally {
        // Unlock first, then close — both for this descriptor
        // only, and never for a descriptor that
        // lost the lock to a close elsewhere.
        try {
          await raf.unlock();
        } on FileSystemException {
          // Already gone; the close below finishes the job.
        }
        await raf.close();
      }
    }
  }

  /// Opens the sidecar read-write without truncating, creating
  /// the document's directory on first use like the
  /// baseline's `lock()` (`mkdir -p` before `O_CREAT | O_RDWR`).
  ///
  /// Every failure surfaces as an `STORAGE_ERROR`
  /// [AisetFailure] — a lock that cannot even be attempted is
  /// a storage problem, not a timeout, and the port's
  /// contract is stable codes rather than raw OS exceptions.
  Future<RandomAccessFile> _openSidecar() async {
    final file = File(sidecarPath);
    try {
      return await file.open(mode: FileMode.append);
    } on FileSystemException {
      // A missing parent directory is the normal state of a first
      // write into a new location; anything else fails the
      // retry below and lands in the refusal.
      try {
        await file.parent.create(recursive: true);
        return await file.open(mode: FileMode.append);
      } on FileSystemException catch (error) {
        throw AisetFailure(
          AisetErrorCode.storageError,
          'The storage lock file could not be opened',
          detail: error.osError?.message ?? error.message,
        );
      }
    }
  }

  /// The queue key: the sidecar path with symlinks resolved where
  /// possible, falling back to the absolute path. Same-process aliasing
  /// of one file through two spellings still lands on one queue in
  /// the ordinary case, and the OS lock remains the real guard
  /// across processes either way.
  String _canonicalSidecarPath() {
    final file = File(sidecarPath);
    try {
      return file.resolveSymbolicLinksSync();
    } on FileSystemException {
      // The sidecar may not exist yet; resolve its directory instead.
      try {
        final name = file.uri.pathSegments.last;
        return '${file.parent.resolveSymbolicLinksSync()}/$name';
      } on FileSystemException {
        return file.absolute.path;
      }
    }
  }
}
