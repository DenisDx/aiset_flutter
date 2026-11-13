import 'dart:io';

import 'package:test/test.dart';

import 'fixtures_io.dart';

void main() {
  test('pubspec declares no Flutter dependency (LIB-03)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(matches(RegExp(r'^\s*flutter\s*:', multiLine: true))),
        reason: 'aiset_core must stay pure Dart');
    expect(pubspec, isNot(contains('sdk: flutter')));
    expect(pubspec, contains('name: aiset_core'));
  });

  test('fixtures/preservation holds only data plus the manifest', () {
    final dir = preservationDir();
    final entries = dir.listSync().map((e) => e.path.split('/').last).toSet();
    expect(entries, equals({'manifest.json', 'cases'}));

    final files = Directory('${dir.path}/cases').listSync();
    expect(files, isNotEmpty);
    for (final file in files) {
      final name = file.path.split('/').last;
      expect(name, matches(RegExp(r'\.(input|expected)\.json5$')),
          reason: 'unexpected file in fixtures: $name');
    }
    // Every manifest case has exactly its input and expected files,
    // and every file belongs to a manifest case.
    final cases = PreservationCase.loadAll();
    final expectedNames = <String>{
      for (final c in cases) ...['${c.id}.input.json5', '${c.id}.expected.json5'],
    };
    expect(files.map((f) => f.path.split('/').last).toSet(), equals(expectedNames));
  });

  test('fixture data files carry no Python or pytest artifacts', () {
    final dir = preservationDir();
    for (final file in Directory('${dir.path}/cases').listSync().whereType<File>()) {
      final content = file.readAsStringSync();
      expect(content, isNot(contains('import ')), reason: file.path);
      expect(content, isNot(contains('def ')), reason: file.path);
      expect(content, isNot(contains('pytest')), reason: file.path);
    }
  });
}
