import 'package:aiset_core/aiset_core.dart';
import 'package:test/test.dart';

/// The two forms of descriptor `description` and `title`, and the
/// resolution rules of `SPEC_.md` amendment 41.
///
/// These rules are authored here rather than generated:
/// the corpus pins the shared grammar (case
/// `descriptor_validate/description_object_form.json`, executed against the
/// re-baselined commit `d4adb45` where the upstream F1 change landed),
/// while the amendment-41 resolution order, the host
/// translator boundary and the error-table behavior are Dart-side
/// requirements the Python side does not pin. The
/// language-tag grammar is aligned only for the shape,
/// not for tag normalization and region fallback; `local_aiset_python_notes.md`
/// F2 records that open question, and this suite deliberately
/// keeps testing the Dart rules as written.
void main() {
  const wrapper = {
    'default': 'en',
    'text': {'en': 'Retry count', 'ru': 'Число попыток'},
  };

  group('string form', () {
    test('a string is the text and its own translation key', () {
      final text = readDescriptorText('Number of retry attempts',
          path: '/root/children/a/description', report: (_, _, _) {});
      expect(text, isA<PlainText>());
      expect(text!.defaultText, equals('Number of retry attempts'));
    });

    test('an untranslated string is shown verbatim, never empty or keyed', () {
      final text = PlainText('Retry count');
      expect(text.resolve(language: 'ru'), equals('Retry count'));
    });

    test('a host translator supplies the string form for the active locale', () {
      const text = PlainText('Retry count');
      String? translator(String key, String language) =>
          key == 'Retry count' && language == 'ru' ? 'Число попыток' : null;
      expect(text.resolve(language: 'ru', translator: translator),
          equals('Число попыток'));
      expect(text.resolve(language: 'de', translator: translator),
          equals('Retry count'));
    });

    test('a resolved value is not translated a second time', () {
      var calls = 0;
      String? translator(String key, String language) {
        calls++;
        return key == 'Retry count' ? 'Anzahl' : 'RE-TRANSLATED';
      }

      const PlainText('Retry count')
          .resolve(language: 'de', translator: translator);
      expect(calls, equals(1));
      // A translation the host returned is final: it is never fed
      // back through the translator.
      expect(
          PlainText('Retry count').resolve(language: 'de', translator: translator),
          equals('Anzahl'));
      expect(calls, equals(2));
    });
  });

  group('wrapper form', () {
    test('the active locale entry is used', () {
      final text = readDescriptorText(wrapper,
          path: '/root/children/a/description', report: (_, _, _) {})!;
      expect(text.resolve(language: 'ru'), equals('Число попыток'));
      expect(text.resolve(language: 'en'), equals('Retry count'));
    });

    test('an unavailable locale falls back to the declared default', () {
      final text = readDescriptorText(wrapper,
          path: '/root/children/a/description', report: (_, _, _) {})!;
      expect(text.resolve(language: 'de'), equals('Retry count'));
    });

    test('a locale-unaware reader gets the default-language string', () {
      final text = readDescriptorText(wrapper,
          path: '/root/children/a/description', report: (_, _, _) {})!;
      expect(text.defaultText, equals('Retry count'));
      expect(text.resolve(), equals('Retry count'));
    });

    test('without a declared default the document language is used', () {
      final text = readDescriptorText(
        {
          'text': {'en': 'Retry count', 'ru': 'Число попыток'},
        },
        path: '/root/children/a/description',
        report: (_, _, _) {},
      )!;
      expect(text.defaultText, equals('Retry count'));
      expect(text.resolve(language: 'ja'), equals('Retry count'));
    });

    test('the document language can be chosen by the reader', () {
      final text = readDescriptorText(
        {
          'text': {'en': 'Retry count', 'ru': 'Число попыток'},
        },
        path: '/d',
        report: (_, _, _) {},
        defaultLanguage: 'ru',
      )!;
      expect(text.defaultText, equals('Число попыток'));
    });

    test('an inline object is final: the host translator does not override it', () {
      final text = readDescriptorText(wrapper, path: '/d', report: (_, _, _) {})!;
      String? translator(String key, String language) => 'OVERRIDDEN';
      expect(text.resolve(language: 'en', translator: translator),
          equals('Retry count'));
    });

    test('a region-qualified locale finds the language entry', () {
      final text = readDescriptorText(wrapper, path: '/d', report: (_, _, _) {})!;
      expect(text.resolve(language: 'ru-RU'), equals('Число попыток'));
      expect(text.resolve(language: 'en-GB'), equals('Retry count'));
    });
  });

  group('language tags', () {
    test('tags are normalized case-insensitively', () {
      expect(normalizeLanguageTag('RU'), equals('ru'));
      expect(normalizeLanguageTag('zh-hans'), equals('zh-Hans'));
      expect(normalizeLanguageTag('en-us'), equals('en-US'));
      expect(normalizeLanguageTag('sr-Latn-RS'), equals('sr-Latn-RS'));
    });

    test('a tag written in a different case still resolves', () {
      final text = readDescriptorText(
        {
          'default': 'EN',
          'text': {'RU': 'Число попыток', 'EN': 'Retry count'},
        },
        path: '/d',
        report: (_, _, _) {},
      )!;
      expect(text.resolve(language: 'ru'), equals('Число попыток'));
      expect(text.defaultText, equals('Retry count'));
    });

    test('a well-formed tag no reader uses is ignored', () {
      final issues = <String>[];
      final text = readDescriptorText(
        {
          'default': 'en',
          'text': {'en': 'Retry count', 'ja': 'リトライ回数'},
        },
        path: '/d',
        report: (path, message, _) => issues.add('$path: $message'),
      )!;
      expect(issues, isEmpty);
      expect(text.resolve(language: 'en'), equals('Retry count'));
      expect(text.resolve(language: 'de'), equals('Retry count'));
    });

    test('the lookup chain drops trailing subtags', () {
      expect(lookupTags('zh-Hans-CN'), equals(['zh-Hans-CN', 'zh-Hans', 'zh']));
      expect(lookupTags('en'), equals(['en']));
      expect(lookupTags('not a tag'), isEmpty);
    });

    test('a malformed tag is rejected', () {
      for (final tag in [
        '', 'e', ' four ', 'toolongtag', '12', 'en-', '-en', 'en..US', 'en_US',
        'ру', 'en-x', 'en-1', 'en-12', 'en-123456789', 'en--US',
      ]) {
        expect(normalizeLanguageTagOrNull(tag), isNull, reason: 'accepted "$tag"');
      }
    });

    test('a malformed tag inside text is a descriptor error at that entry', () {
      final issues = <String, String>{};
      final text = readDescriptorText(
        {
          'default': 'en',
          'text': {'en': 'Retry count', 'en_US': 'x'},
        },
        path: '/root/children/a/description',
        report: (path, message, _) => issues[path] = message,
      );
      expect(text, isNull);
      expect(issues.keys,
          contains('/root/children/a/description/text/en_US'));
    });
  });

  group('error table', () {
    List<String> errorsOf(Object? value, {String defaultLanguage = 'en'}) {
      final reported = <String, String>{};
      final text = readDescriptorText(
        value,
        path: '/root/children/a/description',
        report: (path, message, _) => reported[path] = message,
        defaultLanguage: defaultLanguage,
      );
      if (text == null && reported.isEmpty) reported['<unspecified>'] = 'rejected';
      return reported.keys.toList();
    }

    test('an empty localized text is an error', () {
      expect(errorsOf(<String, Object?>{
        'default': 'en',
        'text': <String, Object?>{},
      }), contains('/root/children/a/description/text'));
    });

    test('an object without text is an error', () {
      expect(errorsOf({'default': 'en'}),
          contains('/root/children/a/description'));
    });

    test('a bare language map is rejected', () {
      expect(
          errorsOf({'en': 'Retry count', 'ru': 'Число попыток'}),
          contains('/root/children/a/description'),
          reason: 'a bare map is ambiguous with an object-valued setting');
    });

    test('a text entry that is not a string is an error at that entry', () {
      expect(errorsOf({
        'default': 'en',
        'text': {'en': 5},
      }), contains('/root/children/a/description/text/en'));
      expect(errorsOf({
        'default': 'en',
        'text': {'en': {'nested': 'map'}},
      }), contains('/root/children/a/description/text/en'));
      expect(errorsOf({
        'default': 'en',
        'text': {'en': ''},
      }), contains('/root/children/a/description/text/en'));
    });

    test('a default naming an absent tag is an error', () {
      expect(errorsOf({
        'default': 'de',
        'text': {'en': 'Retry count'},
      }), contains('/root/children/a/description/default'));
    });

    test('no default and no document language present is an error', () {
      expect(
          errorsOf({
            'text': {'ru': 'Число попыток'},
          }),
          contains('/root/children/a/description'));
      // The same content is fine for a Russian document.
      expect(
          errorsOf(<String, Object?>{'text': <String, Object?>{'ru': 'Число попыток'}},
              defaultLanguage: 'ru'),
          isEmpty);
    });

    test('an unknown key inside the wrapper is an error', () {
      final paths = errorsOf({
        'defualt': 'en',
        'text': {'en': 'Retry count'},
      });
      expect(paths, contains('/root/children/a/description/defualt'),
          reason: 'a misspelled default must not silently disable the rule');
      expect(paths.length, equals(1),
          reason: 'the typo is the problem; no second diagnostic is invented');
    });

    test('a malformed default tag is an error', () {
      expect(errorsOf({
        'default': 'english',
        'text': {'en': 'Retry count'},
      }), contains('/root/children/a/description/default'));
    });

    test('a language declared twice is an error', () {
      expect(errorsOf({
        'default': 'en',
        'text': {'RU': 'a', 'ru': 'b'},
      }), contains('/root/children/a/description/text/ru'));
    });

    test('a non-string non-object value is a property type error', () {
      expect(errorsOf(5), contains('/root/children/a/description'));
      expect(errorsOf(['a']), contains('/root/children/a/description'));
    });

    test('the two diagnostic kinds are distinguished', () {
      // A value that is neither accepted form is a property type problem;
      // a wrapper that is present but malformed inside is a structure problem.
      DescriptorIssue onlyIssue(Object? value) {
        final diagnostic = validateDescriptor('{ descriptor_version: "1.0",'
            ' root: { type: "object", children: { a: { type: "int", description: $value } } } }');
        return diagnostic.issues.single;
      }

      expect(onlyIssue('5').code, equals('INVALID_PROPERTY_TYPE'));
      expect(onlyIssue('{ text: { en: 5 } }').code, equals('INVALID_STRUCTURE'));
      expect(onlyIssue('{ defualt: "en", text: { en: "x" } }').code,
          equals('INVALID_STRUCTURE'));
      expect(onlyIssue('{ text: { "en_US": "x" } }').code,
          equals('INVALID_STRUCTURE'));
    });
  });

  group('comments and precedence', () {
    test('a declared field wins over a source comment', () {
      final text = readDescriptorText('Retry count', path: '/d', report: (_, _, _) {})!;
      expect(
          resolveDescription(
              field: text, commentText: 'A comment that explains nothing'),
          equals('Retry count'));
    });

    test('a comment supplies the description when no field does', () {
      expect(
          resolveDescription(commentText: 'How many times to retry'),
          equals('How many times to retry'));
    });

    test('a comment is default-language text and is never translated', () {
      String? translator(String key, String language) => 'TRANSLATED';
      expect(
          resolveDescription(
              commentText: 'How many times to retry',
              language: 'ru',
              translator: translator),
          equals('How many times to retry'));
    });

    test('a localized field resolved for a locale beats the comment', () {
      final text = readDescriptorText(wrapper, path: '/d', report: (_, _, _) {})!;
      expect(
          resolveDescription(
              field: text, commentText: 'comment', language: 'ru'),
          equals('Число попыток'));
    });

    test('nothing declared and no comment yields no description', () {
      expect(resolveDescription(), isNull);
    });
  });

  group('title behaves identically', () {
    test('string and wrapper forms resolve the same way', () {
      final plain = readDescriptorText('Retries', path: '/t', report: (_, _, _) {})!;
      final wrapped = readDescriptorText({
        'default': 'en',
        'text': {'en': 'Retries', 'ru': 'Повторы'},
      }, path: '/t', report: (_, _, _) {})!;
      expect(plain.resolve(language: 'ru'), equals('Retries'));
      expect(wrapped.resolve(language: 'ru'), equals('Повторы'));
      expect(wrapped.resolve(language: 'kk'), equals('Retries'));
    });

    test('the compiler carries both fields in both forms', () {
      final compiled = compileDescriptor('''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    retries: {
      type: "int",
      title: { default: "en", text: { en: "Retries", ru: "Повторы" } },
      description: { text: { en: "How many times to retry", ru: "Сколько раз повторить" } },
    },
  } },
}
''');
      final node = compiled.nodeAt('/retries')!;
      expect(node.title?.resolve(language: 'ru'), equals('Повторы'));
      expect(node.description?.resolve(language: 'ru'),
          equals('Сколько раз повторить'));
      expect(node.description?.defaultText, equals('How many times to retry'));
    });

    test('a malformed wrapper is a descriptor error that refuses compilation', () {
      expect(
          () => compileDescriptor('''
{
  descriptor_version: "1.0",
  root: { type: "object", children: {
    retries: { type: "int", description: { text: { de: 'Nur Deutsch' } } },
  } },
}
'''),
          throwsA(isA<DescriptorException>()));
    });
  });
}
