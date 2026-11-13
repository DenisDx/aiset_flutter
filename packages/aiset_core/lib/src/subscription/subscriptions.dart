part of 'subscription.dart';

// `UnmodifiableListView` is the registry's read view.

/// A registered subscription and its cancellation handle
/// (`SPEC.md` amendment 9).
///
/// A subscription is filtered by [document] and by [paths]: it is
/// notified when a changed pointer equals a watched pointer, is inside
/// one, or contains one — an edit that replaces a whole object
/// changes its children too, and a watcher of a child must hear
/// about it. The handle cancels with [cancel], which is idempotent.
///
/// [minSeverity] lets a host subscribe to warnings only
/// or to everything; the service passes the permission
/// filter in front of the delivery, so a subscriber
/// that may not read a secret subtree is never
/// notified about a path under it.
final class SubscriptionHandle {
  /// Created by the service; hosts do not build these.
  SubscriptionHandle._({
    required this.id,
    required this.document,
    required List<String> paths,
    required this.listener,
    required this.registry,
    this.permissionFilter,
  })  : _paths = List<String>.unmodifiable(paths);

  /// Stable identifier of the registration.
  final int id;

  /// The document this subscription watches.
  final String document;

  /// The watched pointers.
  List<String> get paths => _paths;
  final List<String> _paths;

  /// The host listener.
  final ChangeListener listener;

  /// Whether a changed path may be delivered to this
  /// subscription at all. A false answer drops the event entirely
  /// rather than redacting it: a redacted fragment of a secret subtree
  /// would still disclose its shape (`SPEC.md` amendment 9).
  final bool Function(String changedPath)? permissionFilter;

  /// The registry this handle was registered with; it
  /// owns the live list.
  final SubscriptionRegistry registry;

  /// Whether the subscription still receives events.
  bool get isActive => registry.contains(this);

  /// The watched pointers that [changed] matches.
  List<String> matches(Iterable<String> changed) {
    final out = <String>[];
    for (final path in changed) {
      for (final watched in _paths) {
        if (_overlaps(path, watched)) {
          out.add(path);
          break;
        }
      }
    }
    return out;
  }

  /// Cancels the subscription.
  ///
  /// Safe to call more than once. A delivery already in flight may still
  /// reach the listener, and a cancelled subscription is never
  /// called again (`SPEC.md` amendment 9).
  void cancel() => registry.remove(this);

  @override
  String toString() =>
      'Subscription($id of $document ${_paths.join(", ")}, ${isActive ? "active" : "cancelled"})';
}

/// Whether pointer [a] overlaps watched pointer [b]: equal, inside, or an
/// ancestor. Identical to the baseline's `matches` rule, including the
/// case where the changed path is the shallower of the two.
bool _overlaps(String a, String b) =>
    a == b || a.startsWith('$b/') || b.startsWith('$a/');

/// The registry the service hands out: an ordered, mutable list
/// of live subscriptions.
final class SubscriptionRegistry {
  final List<SubscriptionHandle> _handles = [];
  var _nextId = 1;

  /// The live subscriptions, in registration order — the
  /// documented delivery order.
  List<SubscriptionHandle> get active => UnmodifiableListView(_handles);

  /// Registers a listener for [document] and [paths].
  ///
  /// At least one pointer is required: an empty filter would mean
  /// "everything" and invite a host to subscribe to a
  /// whole document without deciding it.
  SubscriptionHandle subscribe(
    String document,
    List<String> paths,
    ChangeListener listener, {
    bool Function(String changedPath)? permissionFilter,
  }) {
    if (paths.isEmpty) {
      throw AisetFailure(
          AisetErrorCode.badRequest, 'A subscription requires at least one JSON Pointer');
    }
    final handle = SubscriptionHandle._(
      id: _nextId++,
      document: document,
      paths: paths,
      listener: listener,
      registry: this,
      permissionFilter: permissionFilter,
    );
    _handles.add(handle);
    return handle;
  }

  /// Whether [handle] is still registered.
  bool contains(SubscriptionHandle handle) => _handles.contains(handle);

  /// Removes [handle] from the live list.
  void remove(SubscriptionHandle handle) => _handles.remove(handle);

  /// Drops every registration, for a service that is shut
  /// down.
  void clear() => _handles.clear();
}
