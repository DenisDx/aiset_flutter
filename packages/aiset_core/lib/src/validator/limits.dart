part of 'validator.dart';

/// The measurable resource limits of a validation pass
/// (`SPEC.md` amendment 26; the baseline's `Limits`).
///
/// The default profile is the compatibility profile:
/// document and body up to 8 MiB, nesting depth 64,
/// collection size 100 000, string length 1 048 576, pattern length
/// 512. Lengths are counted in Unicode code points
/// (`docs/grammars.md` §1.4) so that the two implementations
/// count one value the same way.
///
/// [regexBudgetMs] and [budgetSubjectLength] mirror the baseline's
/// timeout profile. This product does not run a
/// background timer: `SPEC.md` amendment 26 forbids promising a safe
/// timeout through an ordinary `Future`, and `docs/grammars.md` §1.5 makes the
/// accepted dialect itself the guarantee — the constructs that make
/// matching explosive are refused before any match. The fields are
/// carried so a profile dump matches the baseline's numbers.
final class Limits {
  /// Creates a limit profile; every default is the
  /// compatibility profile of `SPEC.md` amendment 26.
  const Limits({
    this.maxFileSize = 8 * 1024 * 1024,
    this.maxBodySize = 8 * 1024 * 1024,
    this.maxDepth = 64,
    this.maxCollectionSize = 100000,
    this.maxStringLength = 1024 * 1024,
    this.maxPatternLength = 512,
    this.regexBudgetMs = 100,
    this.budgetSubjectLength = 4096,
  });

  /// The largest document or body accepted, in bytes. Enforced by the
  /// storage adapters (slice 2E), not by the value walk.
  final int maxFileSize;

  /// The largest request body accepted, in bytes.
  final int maxBodySize;

  /// The deepest nesting of containers a value may hold.
  final int maxDepth;

  /// The most keys an object, or the most items an array, may hold.
  final int maxCollectionSize;

  /// The longest text a value or an object key may hold, in code points.
  final int maxStringLength;

  /// The longest `pattern` or `key_pattern`, in code points.
  final int maxPatternLength;

  /// The baseline's regex budget in milliseconds, carried for
  /// profile parity (see the class comment; no timer is armed).
  final int regexBudgetMs;

  /// The subject length from which the baseline would guard a match
  /// with a worker thread; carried for profile parity.
  final int budgetSubjectLength;

  /// The default compatibility profile.
  static const Limits defaultProfile = Limits();
}

/// The cheap structural limits, applied before any constraint is evaluated.
///
/// The walk reports:
///
/// * `max_depth` — a container nested deeper than [Limits.maxDepth];
///   the issue is reported at the over-deep node and its subtree is not
///   walked further, so one deep chain yields one issue.
/// * `max_collection_size` — an object or array over [Limits.maxCollectionSize],
///   reported at the container.
/// * `max_string_length` — a text value or an object key over
///   [Limits.maxStringLength]; a key is reported at its
///   container, exactly as the executed baseline does.
/// * `finite` — a non-finite number anywhere in the tree.
///
/// The issues are returned in walk order. They are
/// never a crash and never silently drop data.
List<ValidationIssue> checkLimits(Object? value, {Limits limits = Limits.defaultProfile}) {
  final out = <ValidationIssue>[];

  void walk(Object? node, String path, int depth) {
    if (depth > limits.maxDepth) {
      out.add(ValidationIssue(
          rule: 'max_depth',
          path: path,
          message: 'Depth exceeds ${limits.maxDepth}'));
      return;
    }
    final map = _asStringMap(node);
    if (map != null) {
      if (map.length > limits.maxCollectionSize) {
        out.add(ValidationIssue(
            rule: 'max_collection_size',
            path: path,
            message: 'Object exceeds ${limits.maxCollectionSize} keys'));
      }
      map.forEach((key, item) {
        if (key.runes.length > limits.maxStringLength) {
          out.add(ValidationIssue(
              rule: 'max_string_length',
              path: path,
              message: 'Object key is too long'));
        }
        walk(item, '$path/${escapePointerToken(key)}', depth + 1);
      });
      return;
    }
    final items = _asList(node);
    if (items != null) {
      if (items.length > limits.maxCollectionSize) {
        out.add(ValidationIssue(
            rule: 'max_collection_size',
            path: path,
            message: 'Array exceeds ${limits.maxCollectionSize} items'));
      }
      for (var index = 0; index < items.length; index++) {
        walk(items[index], '$path/$index', depth + 1);
      }
      return;
    }
    if (node is String) {
      if (node.runes.length > limits.maxStringLength) {
        out.add(ValidationIssue(
            rule: 'max_string_length',
            path: path,
            message: 'String exceeds ${limits.maxStringLength} characters'));
      }
      return;
    }
    if (node is double && !node.isFinite) {
      out.add(ValidationIssue(
          rule: 'finite', path: path, message: 'Value must be finite'));
    }
  }

  walk(value, '', 0);
  return out;
}
