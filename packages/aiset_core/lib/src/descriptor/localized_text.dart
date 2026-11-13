part of 'descriptor.dart';

/// Reports one problem with a localized-text value.
///
/// [wrongValueType] distinguishes a value that is neither of the two
/// accepted forms from a wrapper that is present but malformed inside, so
/// the diagnostic carries the accurate code.
typedef DescriptorTextIssue = void Function(
    String path, String message, bool wrongValueType);

/// A host-supplied translation of descriptor text.
///
/// [key] is the descriptor's own string, [language] is the
/// normalized BCP-47 tag being rendered, and the return value is the
/// translation or `null` when the host has none.
typedef DescriptorTranslator = String? Function(String key, String language);

/// The user-facing text of a descriptor `description` or `title`, in
/// either of the two forms of `SPEC_.md` amendment 41.
///
/// * [DescriptorText.plain] — a string, which doubles as its own
///   translation key and is shown verbatim when nothing translates it.
/// * [LocalizedText] — the wrapper `{ default, text }` mapping normalized
///   language tags to strings.
///
/// A resolved value is never passed through a later step again, and a
/// locale-unaware reader always gets a string: [resolve] with no locale
/// returns the default-language text.
sealed class DescriptorText {
  /// Sealed base for the two descriptor text forms.
  const DescriptorText();

  /// The text a reader with no locale preference displays: the
  /// default-language entry of a [LocalizedText], or the string itself.
  String get defaultText;

  /// The text shown to a reader of [language], optionally translated by a
  /// host [translator].
  ///
  /// Resolution order (`SPEC_.md` 41 R5): the entry for [language]; otherwise a
  /// host translation of the string key; otherwise the default-language entry;
  /// otherwise the string itself.
  String resolve({String? language, DescriptorTranslator? translator});

  /// The form used in diagnostics and envelopes.
  String get form;
}

/// The string form of descriptor text, which is also its translation key.
final class PlainText extends DescriptorText {
  /// Creates the string form.
  const PlainText(this.text);

  /// The text as written in the descriptor.
  final String text;

  @override
  String get defaultText => text;

  @override
  String resolve({String? language, DescriptorTranslator? translator}) {
    if (translator != null && language != null) {
      final translated = translator(text, language);
      if (translated != null && translated.isNotEmpty) return translated;
    }
    return text;
  }

  @override
  String get form => 'string';

  @override
  bool operator ==(Object other) => other is PlainText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'PlainText($text)';
}

/// The language-tagged wrapper form: `{ default: 'en', text: { en: …, ru: … } }`.
final class LocalizedText extends DescriptorText {
  /// Creates a wrapper. [entries] is keyed by normalized BCP-47 tag,
  /// [defaultLanguage] is the language a locale-unaware reader gets, and
  /// [declaredDefault] is the `default` key when the descriptor named one.
  const LocalizedText({
    required this.entries,
    required this.defaultLanguage,
    this.declaredDefault,
  });

  /// Normalized language tag to text, in descriptor order.
  final Map<String, String> entries;

  /// The language this text falls back to: the declared `default`,
  /// or the descriptor document's default language.
  final String defaultLanguage;

  /// The language the descriptor itself declared, or `null` when it
  /// relies on the document default.
  final String? declaredDefault;

  @override
  String get defaultText => entries[defaultLanguage]!;

  @override
  String resolve({String? language, DescriptorTranslator? translator}) {
    // An inline object is final: the host translator applies to the
    // string form only (SPEC_.md 41, open point recorded as "no").
    if (language != null) {
      final exact = entries[normalizeLanguageTag(language)];
      if (exact != null) return exact;
      for (final candidate in lookupTags(language)) {
        final value = entries[candidate];
        if (value != null) return value;
      }
    }
    return entries[defaultLanguage]!;
  }

  @override
  String get form => 'localized';

  @override
  bool operator ==(Object other) =>
      other is LocalizedText &&
      other.declaredDefault == declaredDefault &&
      _sameStringMap(other.entries, entries);

  @override
  int get hashCode =>
      Object.hash(declaredDefault, defaultLanguage, entries.length, entries.values.join('\u0000'));

  @override
  String toString() => 'LocalizedText(default: $declaredDefault, $entries)';
}

bool _sameStringMap(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// The document default language a descriptor falls back to when it declares
/// none (`SPEC_.md` amendment 41).
const String defaultDescriptorLanguage = 'en';

/// The description a reader sees for one node.
///
/// The declared `description` [field] wins; otherwise the source [commentText]
/// supplies the description as default-language text that is never translated,
/// because translating it would mean rewriting the user's settings file
/// (`SPEC_.md` amendment 41 R6). Returns `null` when the node has neither.
String? resolveDescription({
  DescriptorText? field,
  String? commentText,
  String? language,
  DescriptorTranslator? translator,
}) {
  if (field != null) {
    return field.resolve(language: language, translator: translator);
  }
  return commentText;
}

/// Reads one `description` or `title` value, reporting every violation of
/// `SPEC_.md` amendment 41 as a diagnostic on [path].
///
/// Returns `null` when the value is absent. A value that is present but
/// malformed yields `null` after adding its issues, so the
/// caller never has to guess whether the field was wrong.
DescriptorText? readDescriptorText(
  Object? value, {
  required String path,
  required DescriptorTextIssue report,
  String defaultLanguage = defaultDescriptorLanguage,
}) {
  if (value == null) return null;
  if (value is String) return PlainText(value);
  if (value is! Map<String, Object?>) {
    report(path, 'must be a string or a { default, text } object', true);
    return null;
  }

  for (final key in value.keys) {
    if (!DescriptorGrammar.localizedTextKeys.contains(key)) {
      report('$path/$key',
          'Unknown key in localized text; recognized: default, text', false);
    }
  }

  final rawText = value['text'];
  if (rawText == null) {
    report(path, 'localized text requires a "text" map of language tag to string',
        false);
    return null;
  }
  if (rawText is! Map<String, Object?>) {
    report('$path/text', 'text must be a map of language tag to string', false);
    return null;
  }
  if (rawText.isEmpty) {
    report('$path/text', 'localized text must not be empty', false);
    return null;
  }

  final entries = <String, String>{};
  var malformed = false;
  rawText.forEach((tag, entry) {
    final normalized = normalizeLanguageTagOrNull(tag);
    if (normalized == null) {
      report('$path/text/$tag', '"$tag" is not a well-formed BCP-47 language tag',
          false);
      malformed = true;
      return;
    }
    if (entry is! String) {
      report('$path/text/$normalized', 'text for $normalized must be a string',
          false);
      malformed = true;
      return;
    }
    if (entry.isEmpty) {
      report('$path/text/$normalized', 'text for $normalized must not be empty',
          false);
      malformed = true;
      return;
    }
    if (entries.containsKey(normalized)) {
      report('$path/text/$tag', 'language $normalized is declared twice', false);
      malformed = true;
      return;
    }
    entries[normalized] = entry;
  });

  String? declaredDefault;
  final rawDefault = value['default'];
  if (rawDefault != null) {
    if (rawDefault is! String) {
      report('$path/default', 'default must be a language tag string', false);
      malformed = true;
    } else {
      declaredDefault = normalizeLanguageTagOrNull(rawDefault);
      if (declaredDefault == null) {
        report('$path/default', '"$rawDefault" is not a well-formed BCP-47 language tag',
            false);
        malformed = true;
      } else if (!entries.containsKey(declaredDefault)) {
        report('$path/default',
            'the default language $declaredDefault has no entry in text', false);
        malformed = true;
      }
    }
  }

  final resolvedDefault = declaredDefault ?? defaultLanguage;
  if (!malformed && !entries.containsKey(resolvedDefault)) {
    report(path,
        'localized text has no entry for the default language $resolvedDefault', false);
    malformed = true;
  }
  if (malformed) return null;
  return LocalizedText(
    entries: entries,
    defaultLanguage: resolvedDefault,
    declaredDefault: declaredDefault,
  );
}

/// Normalizes [tag] to canonical BCP-47 form: `RU` → `ru`,
/// `zh-hans` → `zh-Hans`, `en-us` → `en-US`.
///
/// Throws [FormatException] for a malformed tag; use
/// [normalizeLanguageTagOrNull] where the failure must be reported instead.
String normalizeLanguageTag(String tag) {
  final normalized = normalizeLanguageTagOrNull(tag);
  if (normalized == null) {
    throw FormatException('"$tag" is not a well-formed BCP-47 language tag');
  }
  return normalized;
}

/// The canonical form of [tag], or `null` when [tag] is not a well-formed
/// BCP-47 language tag.
String? normalizeLanguageTagOrNull(String tag) {
  if (tag.isEmpty) return null;
  final subtags = tag.split('-');
  if (subtags.any((part) => part.isEmpty)) return null;
  final primary = subtags.first;
  if (!_isAlpha(primary) || primary.length < 2 || primary.length > 3) return null;
  final out = <String>[primary.toLowerCase()];
  var index = 1;
  // Optional script, then optional region.
  if (index < subtags.length && _isAlpha(subtags[index]) && subtags[index].length == 4) {
    out.add(_titleCase(subtags[index]));
    index++;
  }
  if (index < subtags.length && _regionForm(subtags[index])) {
    out.add(subtags[index].toUpperCase());
    index++;
  }
  while (index < subtags.length) {
    final part = subtags[index];
    if (part.length == 1 && _isAlnum(part)) {
      // A singleton introduces an extension or the private-use block and is
      // never a complete subtag on its own.
      if (index == subtags.length - 1) return null;
      if (part.toLowerCase() == 'x') {
        for (final rest in subtags.sublist(index + 1)) {
          if (rest.length > 8 || !_isAlnum(rest)) return null;
        }
        out
          ..add('x')
          ..addAll(subtags.sublist(index + 1).map((p) => p.toLowerCase()));
        return out.join('-');
      }
      final following = subtags[index + 1];
      if (following.length < 3 ||
          following.length > 8 ||
          !_isAlnum(following)) {
        return null;
      }
      out
        ..add(part.toLowerCase())
        ..add(following.toLowerCase());
      index += 2;
      continue;
    }
    final isVariant =
        _isAlnum(part) && part.length >= 5 && part.length <= 8;
    final isNumericVariant = RegExp(r'^[0-9][A-Za-z0-9]{3}$').hasMatch(part);
    if (isVariant || isNumericVariant) {
      out.add(part.toLowerCase());
      index++;
      continue;
    }
    return null;
  }
  return out.join('-');
}

/// The RFC 4647 lookup chain for [language]: the tag itself, then with trailing
/// subtags removed, so a reader asking for `ru-RU` finds an `ru` entry.
List<String> lookupTags(String language) {
  final normalized = normalizeLanguageTagOrNull(language);
  if (normalized == null) return const [];
  final parts = normalized.split('-');
  final out = <String>[];
  for (var length = parts.length; length >= 1; length--) {
    // A singleton subtag is an extension prefix: truncating before it would
    // produce a tag that means something else.
    if (parts[length - 1].length == 1) continue;
    out.add(parts.sublist(0, length).join('-'));
  }
  return out;
}

bool _isAlpha(String value) => RegExp(r'^[A-Za-z]+$').hasMatch(value);
bool _isAlnum(String value) => RegExp(r'^[A-Za-z0-9]+$').hasMatch(value);
bool _regionForm(String value) =>
    (_isAlpha(value) && value.length == 2) || (RegExp(r'^[0-9]{3}$').hasMatch(value));
String _titleCase(String value) =>
    value.substring(0, 1).toUpperCase() + value.substring(1).toLowerCase();
