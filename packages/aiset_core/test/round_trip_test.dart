import 'dart:convert';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

import 'fixtures_io.dart';

void main() {
  final cases = PreservationCase.loadAll();

  test('corpus is present and covers the required edge classes', () {
    expect(cases, hasLength(greaterThanOrEqualTo(20)));
    final allClasses = {for (final c in cases) ...c.classes};
    for (final required in [
      'bom',
      'crlf',
      'no-final-newline',
      'comments',
      'astral',
      'unicode',
      'template',
      'escapes',
      'mixed-indentation',
    ]) {
      expect(allClasses, contains(required), reason: 'no case covers $required');
    }
    expect(cases.where((c) => c.origin == 'python-baseline'), isNotEmpty);
    expect(cases.where((c) => c.origin == 'authored'), isNotEmpty);
  });

  for (final testCase in cases) {
    test('round-trip identity: ${testCase.id}', () {
      final document = parse(testCase.inputText);

      // The CST, not the stored string, produces the output.
      final rebuilt = document.toSource();
      expect(rebuilt, equals(testCase.inputText),
          reason: '${testCase.id}: toSource() differs from the input text');

      final actualBytes = utf8.encode(rebuilt);
      final difference = firstByteDifference(actualBytes, testCase.expectedBytes);
      expect(difference, isNull,
          reason: '${testCase.id}: ${difference ?? ''}');
      expect(document.text, equals(testCase.inputText));
    });
  }
}
