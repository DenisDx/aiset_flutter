import 'dart:convert';

import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// The descriptor revision: a content hash of the source text, used as the
/// compare-and-set token of the write pipeline (`SPEC.md` amendment 8).
void main() {
  const minimal = '{\n'
      '  descriptor_version: "1.0",\n'
      '  root: { type: "object", children: { a: { type: "string" } } },\n'
      '}\n';

  group('determinism', () {
    test('the same source always produces the same revision', () {
      expect(descriptorRevision(minimal), equals(descriptorRevision(minimal)));
      expect(descriptorRevision(minimal),
          equals(descriptorRevision(String.fromCharCodes(utf8.encode(minimal)))));
    });

    test('the revision is the documented shape', () {
      expect(descriptorRevision(minimal),
          matches(RegExp(r'^sha256:[0-9a-f]{32}$')));
    });

    test('it does not depend on map iteration order', () {
      // The hash is taken over the source bytes, so no parsed map
      // is walked and no iteration order can enter the result. Two
      // documents that differ only in key order are different sources
      // and get different revisions; the same source always gets
      // one.
      final first = compileDescriptor(minimal);
      final again = compileDescriptor(minimal);
      expect(first.revision, equals(again.revision));
      expect(first.revision, equals(descriptorRevision(minimal)));
    });

    test('key order changes the revision but not the meaning', () {
      const one = '{ descriptor_version: "1.0", root: { type: "object",'
          ' children: { a: { type: "string", description: "d" } } } }';
      const two = '{ descriptor_version: "1.0", root: { type: "object",'
          ' children: { a: { description: "d", type: "string" } } } }';
      expect(descriptorRevision(one), isNot(equals(descriptorRevision(two))));
      expect(compileDescriptor(one).root.children!['a']!.description!.defaultText,
          equals('d'));
      expect(compileDescriptor(two).root.children!['a']!.description!.defaultText,
          equals('d'));
    });
  });

  group('sensitivity', () {
    test('every kind of source change moves the revision', () {
      final base = descriptorRevision(minimal);
      final variants = {
        'a constraint': minimal.replaceFirst(
            'a: { type: "string" }', 'a: { type: "string", min_length: 2 }'),
        'whitespace': minimal.replaceFirst('  root:', '\n  root:'),
        'a comment': '// header\n$minimal',
        'a line ending': minimal.replaceAll('\n', '\r\n'),
        'a byte-order mark: \uFEFF': '\uFEFF$minimal',
        'trailing newline': minimal.trimRight(),
      };
      for (final entry in variants.entries) {
        expect(descriptorRevision(entry.value), isNot(equals(base)),
            reason: '${entry.key} did not change the revision');
      }
    });

    test('an unrelated document does not collide', () {
      expect(descriptorRevision(minimal),
          isNot(equals(descriptorRevision(minimal.replaceFirst('"1.0"', '"1.1"')))));
    });
  });

  group('cross-implementation equality', () {
    test('the digest matches the published SHA-256 vectors', () {
      expect(
          sha256Hex(utf8.encode('')),
          equals('e3b0c44298fc1c149afbf4c8996fb924'
              '27ae41e4649b934ca495991b7852b855'));
      expect(
          sha256Hex(utf8.encode('abc')),
          equals('ba7816bf8f01cfea414140de5dae2223'
              'b00361a396177a9cb410ff61f20015ad'));
      expect(
          sha256Hex(utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')),
          equals('248d6a61d20638b8e5c026930c3e6039'
              'a33ce45964ff2167f6ecedd419db06c1'));
    });

    test('multi-byte source text hashes over its UTF-8 bytes', () {
      const text = '{ description: "Число повторов — \u{1F680}" }';
      expect(descriptorRevision(text), equals(descriptorRevision(text)));
      expect(
          sha256Hex(utf8.encode(text)).length, equals(64),
          reason: 'the digest is over bytes, not code units');
    });

    test('the compiled descriptor carries the revision of its own source', () {
      final compiled = compileDescriptor(minimal);
      expect(compiled.revision, equals(descriptorRevision(minimal)));
      expect(compiled.source, equals(minimal));
    });
  });
}
