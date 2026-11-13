part of 'subscription.dart';

/// The event every subscription and post-commit observer receives
/// (`SPEC.md` amendments 8 and 9).
///
/// It names the changed paths, the revision before and after, the
/// application state and the active revision — the whole
/// of the "what happened to my document" question, and
/// all of it free of values. A secret subtree is
/// never disclosed here: [changedPaths] lists
/// pointers, not contents, and a subscriber without the secret
/// permission is not delivered an event about a secret path at all
/// (see the service's notification step).
final class ChangeEvent {
  /// Creates the event for one committed write.
  const ChangeEvent({
    required this.document,
    required this.changedPaths,
    required this.previousRevision,
    required this.revision,
    required this.applicationState,
    required this.activeRevision,
  });

  /// The registered document id.
  final String document;

  /// The pointers the write changed, sorted.
  final List<String> changedPaths;

  /// The revision the document held before this write.
  final String previousRevision;

  /// The revision this write stored.
  final String revision;

  /// The outcome of application handling: `applied`,
  /// `reload_required`, `restart_required` or `apply_failed`.
  final String applicationState;

  /// The revision the application is running on, which is
  /// [revision] only for an applied `live` change and
  /// otherwise the last revision the host confirmed
  /// (`SPEC.md` amendment 8, APP-01).
  final String activeRevision;

  /// The wire form of the event.
  Map<String, Object?> toMap() => {
        'document': document,
        'changed_paths': List<String>.unmodifiable(changedPaths),
        'previous_revision': previousRevision,
        'revision': revision,
        'application_state': applicationState,
        'active_revision': activeRevision,
      };

  @override
  String toString() =>
      'ChangeEvent($document -> $revision, $applicationState, ${changedPaths.length} paths)';
}

/// A pre-commit probe: it may veto, and it runs
/// before the storage lock is taken.
///
/// [before] and [after] are immutable snapshots of the stored
/// trees; a probe that must decide on a secret value has to
/// hold the secret permission, and the snapshot handed
/// to it is already filtered by the service.
typedef ProbeCallback = FutureOr<Object?> Function(
    Object? before, Object? after, List<String> changedPaths);

/// A post-commit observer: it cannot cancel the committed
/// result, and it runs after the storage lock is released.
typedef AfterSaveCallback = FutureOr<void> Function(
    Object? previous, Object? current, Map<String, Object?> event);

/// The host's domain application for a `live` or `reload`
/// change. Its failure is reported as `apply_failed` with
/// `stored = true`; a committed file is never
/// presented as unsaved because applying it went wrong.
typedef ApplicationCallback = FutureOr<void> Function(
    Object? previous, Object? current, List<String> changedPaths);

/// The notification sink of a subscription.
typedef ChangeListener = FutureOr<void> Function(ChangeEvent event);

/// The sink the service writes its audit records to.
///
/// [payload] never contains a configured value: names, pointers,
/// revisions and the outcome of each step.
typedef AuditSink = void Function(String name, Map<String, Object?> payload);

/// A host veto returned by a pre-commit probe.
///
/// [issues] are reported under `VALIDATION_ERROR`, which is what the
/// amendment asks: the write did not happen and the client is told
/// why by the host rather than by a generic failure.
final class Rejection {
  /// Creates a veto.
  const Rejection(this.issues, {this.message = 'The host rejected this change'});

  /// The structured reasons.
  final List<AisetIssue> issues;

  /// The short reason reported with the code.
  final String message;
}

/// How a callback's bound ended.
enum CallbackOutcome {
  /// The callback finished inside the bound.
  completed,

  /// The bound expired and the callback was cancelled.
  timedOut,

  /// A cancellation token was set before or during the call.
  cancelled,

  /// The callback threw or completed with an error.
  failed,
}

/// The result of one bounded callback call.
final class CallbackResult {
  /// Creates a result.
  const CallbackResult(this.outcome, {this.value, this.error});

  /// How the call ended.
  final CallbackOutcome outcome;

  /// The returned value, for a probe that may answer with a
  /// [Rejection].
  final Object? value;

  /// The failure, for [CallbackOutcome.failed].
  final Object? error;

  /// Whether the callback answered with a veto.
  bool get isRejection => value is Rejection;

  /// The veto, when [isRejection].
  Rejection? get rejection => value is Rejection ? value! as Rejection : null;
}

/// A cooperative cancellation token for a long-running probe.
///
/// A probe that awaits between its steps should pass this to its own
/// work, so that a timeout or a client-side cancel actually
/// stops the extra computation instead of only stopping the
/// pipeline from waiting for it.
final class CallbackCancellation {
  /// Whether cancellation was requested.
  bool get isCancelled => _cancelled;
  var _cancelled = false;

  /// Requests cancellation and wakes anyone waiting on
  /// [onCancel].
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_done.isCompleted) _done.complete();
  }

  final Completer<void> _done = Completer<void>();

  /// A future that completes when [cancel] is called.
  Future<void> get onCancel => _done.future;
}

/// Runs host callbacks with the documented bounds.
///
/// The timeout is the one the service was configured
/// with. On expiry the callback's cancellation token is set and the
/// call is reported as [CallbackOutcome.timedOut]: a probe timeout
/// refuses the write with `CALLBACK_TIMEOUT`, and an observer timeout is
/// logged, because a commit that has
/// happened is not un-happened by a slow listener.
final class CallbackRunner {
  /// Creates a runner bounded by [timeout]; a null timeout
  /// bounds nothing and is only correct in a test.
  const CallbackRunner({this.timeout, this.audit});

  /// The bound applied to every call.
  final Duration? timeout;

  /// Where a swallowed post-commit failure is reported.
  final AuditSink? audit;

  /// Calls [callback] with the given bound, returning the outcome rather than
  /// throwing, so the caller decides what a failure means.
  Future<CallbackResult> call<T extends Object?>(
    FutureOr<T> Function(CallbackCancellation cancel) callback, {
    required String name,
  }) async {
    final cancellation = CallbackCancellation();
    Future<T> run() async {
      final pending = Future<T>.sync(() => callback(cancellation));
      if (timeout == null) return pending;
      return pending.timeout(timeout!, onTimeout: () {
        cancellation.cancel();
        throw _Timeout(name);
      });
    }

    try {
      final value = await run();
      if (cancellation.isCancelled) {
        return CallbackResult(CallbackOutcome.cancelled, value: value);
      }
      return CallbackResult(CallbackOutcome.completed, value: value);
    } on _Timeout {
      return CallbackResult(CallbackOutcome.timedOut);
    } catch (error) {
      return CallbackResult(CallbackOutcome.failed, error: error);
    }
  }

  /// Runs [callback] and reports a failure to [audit] instead of
  /// rethrowing — the post-commit boundary.
  Future<CallbackResult> guarded(
    FutureOr<void> Function(CallbackCancellation cancel) callback, {
    required String name,
  }) async {
    final result = await call<Object?>(callback, name: name);
    if (result.outcome != CallbackOutcome.completed) {
      audit?.call('callback_failed', {
        'callback': name,
        'outcome': result.outcome.name,
        if (result.error != null) 'error': '${result.error.runtimeType}',
      });
    }
    return result;
  }
}

/// Internal marker for a bound that expired.
final class _Timeout implements Exception {
  _Timeout(this.name);
  final String name;
}
