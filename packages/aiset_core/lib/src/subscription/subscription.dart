/// Callbacks, subscriptions and their bounds (`SPEC.md` amendment 9).
///
/// Three host hooks and one notification channel sit on the write
/// path, each with a different authority:
///
/// * a **pre-commit probe** ([ProbeCallback]) sees the candidate before
///   it is stored and MAY veto it by returning a [Rejection];
/// * a **post-commit observer** ([AfterSaveCallback]) sees the committed
///   result and MUST NOT cancel it;
/// * an **application handler** ([ApplicationCallback]) performs the
///   `live`/`reload` domain apply, and its failure turns the result into
///   `apply_failed` while `stored` stays true.
///
/// [SubscriptionHandle] is what `subscribe` returns: a cancellation
/// handle. Subscriptions are filtered by document and path.
///
/// Every callback runs through [CallbackRunner], which bounds it by a
/// timeout and a cancellation token. Post-commit callbacks run after the
/// storage lock is released; because their failure cannot undo
/// a commit, an exception there is reported to the host sink and
/// never rethrown as though the write had not happened.
///
/// The mechanism is Dart-native (`SPEC.md` amendment 30):
/// callbacks are `async` and bounded by a `Future` timeout rather
/// than by a worker thread, and one service serializes its writes with a
/// single in-isolate lock.
library;

import 'dart:async';
import 'dart:collection';

import '../errors/errors.dart';

part 'callbacks.dart';
part 'subscriptions.dart';
