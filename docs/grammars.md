# Grammars: the accepted regex dialect and the bounded-integer policy

This file fixes two decisions that every other layer depends on: which regular-expression
syntax a descriptor may use, and how integers beyond the exactly representable range behave. Both are
implementation decisions within the requirements of `SPEC.md` amendments 5, 25 and 26; neither changes them.

The JSON5 and placeholder grammar itself is not repeated here. It is pinned case by case by the
compatibility corpus under `fixtures/python_compat/` and by the preservation fixtures under
`fixtures/preservation/`; the source-preserving operations on it are described in `ARCHITECTURE.md`.

---

## 1. The accepted regex dialect

Patterns appear in two descriptor fields: `pattern` constrains a string value, `key_pattern` constrains the
keys governed by `additional_children`. Both hold a regular expression in the **accepted dialect** defined
below.

The baseline evaluates patterns with Python `re`; this product evaluates them with Dart `RegExp`, whose
syntax is ECMAScript-based. The two engines are not interchangeable: each compiles constructs the
other rejects, and some constructs mean different things in each. The accepted dialect is therefore the
subset both engines agree on in **syntax and in meaning**, narrowed further by the portability and safety
restrictions `SPEC.md` amendment 26 carries over from the baseline.

A pattern outside the dialect is never reinterpreted, approximated or silently normalized: it is
reported, with the construct that caused it.

### 1.1 Accepted constructs

| Construct | Form |
|---|---|
| Literal character | any character that is not a metacharacter, plus `\\`, `\/`, `\n`, `\r`, `\t`, `\f`, `\v`, `\0`, `\xHH`, `\uHHHH` |
| Any character | `.` — never matches a line break, in either engine |
| Anchors | `^` (start), `$` (end), `\b`, `\B` |
| Character class | `[abc]`, `[^abc]`, ranges `[a-z]`, escapes inside the class |
| Shorthand class | `\d`, `\D`, `\w`, `\W`, `\s`, `\S` — see the ASCII note below |
| Quantifier | `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}`, each also in lazy form with a trailing `?` |
| Group | `(...)` capturing, `(?:...)` non-capturing |
| Alternation | `a|b` |

Capturing groups are accepted because they are ordinary syntax, but nothing may refer back to
them: a group that is never referenced behaves identically in both engines, and a reference does not.

Two semantic notes, both measured against the two engines:

- **`\d`, `\w` and `\b` are ASCII here and Unicode-aware in Python.** Dart does not match an
  Arabic-Indic digit with `\d`, a Cyrillic letter with `\w`, or treat either as a word character for
  `\b`; Python matches all three. `\s` agrees on the common cases, including the non-breaking
  space. A pattern that must classify non-ASCII text states the ranges or the explicit character sets
  it means; relying on the implicit Unicode behavior is not portable.
- **`$` is the end of the subject.** Python also matches it immediately before a single trailing
  newline; Dart does not. Anchored patterns must not depend on that Python behavior. The usual
  `^…$` form is unaffected.

### 1.2 Rejected constructs

Anything not listed in §1.1 is outside the dialect by the same rule: where the two engines do not
agree, the construct is not accepted.

The last column follows one principle. A construct the Dart engine cannot compile is caught when the
descriptor is compiled, and is reported as the descriptor issue `INVALID_PATTERN`. A construct both engines
compile - or one that only Python rejects - cannot be caught by compilation, so the dialect checker
refuses it when a value is validated, as the validation issue with rule `pattern`. The baseline
reports the same constructs at the layer its own engine reaches, which is why the two
implementations can name the same problem differently. The outcome does not differ: the pattern is
refused, named, and never guessed at.

| Rejected | Form | Why it is not portable | Reported as |
|---|---|---|---|
| Named group, Python spelling | `(?P<name>` | Dart cannot compile it | `INVALID_PATTERN` |
| Named backreference, Python spelling | `(?P=name)` | Dart cannot compile it | `INVALID_PATTERN` |
| Inline flag | `(?i)`, `(?s)`, `(?m)`, `(?u)`, `(?x)`, `(?a)`, `(?L)`, `(?U)`, scoped `(?i:…)` | Dart has no inline flags and cannot compile them | `INVALID_PATTERN` |
| Pattern comment | `(?#…)` | Dart cannot compile it | `INVALID_PATTERN` |
| Conditional pattern | `(?(1)…)`, `(?(name)…)` | Dart cannot compile it | `INVALID_PATTERN` |
| Any uncompilable pattern | — | the pattern cannot be evaluated | `INVALID_PATTERN` |
| Lookaround | `(?=`, `(?!`, `(?<=`, `(?<!` | both compile it; the baseline forbids it as outside the portable subset | validation `pattern` |
| Numeric backreference | `\1` … `\99` | both compile it; forbidden as outside the portable subset | validation `pattern` |
| Named group, ECMAScript spelling | `(?<name>` | Python cannot compile it, so no file using it is interoperable | validation `pattern` |
| Named backreference, ECMAScript spelling | `\k<name>` | Python cannot compile it | validation `pattern` |
| Group reference, replacement spelling | `\g<name>` | valid in a Python replacement template, not in a Python pattern | validation `pattern` |
| POSIX class | `[[:alpha:]]` | both compile it as a class of the literal characters `[`, `:`, `a`, `l`, `p`, `h`, with different results | validation `pattern` |
| Python anchors | `\A`, `\Z` | Python anchors them; Dart reads the letters `A` and `Z` | validation `pattern` |
| Unicode property class | `\p{…}`, `\P{…}` | Dart reads a property; Python reads the letter `p` | validation `pattern` |

### 1.3 Where each rejection is reported

The two layers follow the baseline, so a descriptor file is accepted or refused at the same point in both
implementations:

| Situation | Issue | Stable code |
|---|---|---|
| The pattern does not compile, or uses syntax only one engine has | descriptor issue `INVALID_PATTERN`, severity error, path `<node>/pattern`; the descriptor is refused | `INVALID_DESCRIPTOR` |
| The pattern is longer than the limit in §1.4 | validation issue, rule `pattern_length` | `VALIDATION_ERROR` |
| The pattern uses a construct rejected in §1.2 | validation issue, rule `pattern`, message naming the construct ("outside the accepted dialect") | `VALIDATION_ERROR` |
| The value does not match an accepted pattern | validation issue, rule `pattern` | `VALIDATION_ERROR` |
| The match budget in §1.5 is exhausted | validation issue, rule `pattern`, severity **warning**, "check not performed" | none — a check that did not run is not a failed value |

`key_pattern` is checked the same way as `pattern`. The baseline compile-checks only `pattern`, so a
malformed `key_pattern` survives compilation and then fails to match **every** key,
which reads as a data problem rather than a descriptor problem. This product compile-checks both
fields and reports `INVALID_PATTERN` for either; the difference is a correction of a
misleading error, recorded as such (`SPEC.md` amendment 24, `SPEC_.md` amendment 38).

A descriptor that uses a construct only Python can compile — an inline flag, a pattern comment, a
conditional — loads in the baseline and is refused here with `INVALID_PATTERN`. That is the intended
consequence of `SPEC.md` amendment 26, which allows the implementation to refuse an unsupported pattern rather
than guess at it. Such a descriptor is not interoperable in any case: the file that one engine reads
with one meaning, the other reads with another.

### 1.4 Pattern length

A pattern is at most **512** units long (`SPEC.md` amendment 26, the baseline's `max_pattern_length`).
The limit is measured in **Unicode code points**, matching how the baseline counts Python strings;
`String.length` in Dart counts UTF-16 code units and would count an astral character twice, so it is not the
measure. The same unit rule applies to every other length in the product — `min_length`,
`max_length`, `max_string_length` (1048576) — so that a value the baseline counts as one length is not
counted as another here.

The limit is a resource bound, not a style preference: it is checked before the pattern is
compiled or matched, and an over-long pattern is reported as `pattern_length` rather than
handed to the engine.

### 1.5 Matching budget

The compatibility profile carries the baseline's 100 ms regex budget. `SPEC.md` amendment 26
is explicit that a validation path must not promise a safe timeout through an ordinary `Future`: on Web there is
no thread to abandon, and on native an isolate that will not finish is not made safe by
awaiting it. The implementation therefore either bounds the engine it hands the pattern to, or refuses the
pattern before running it. The accepted dialect is what makes refusal rare: with no lookarounds, no
backreferences and no conditionals, the constructs that make matching explosive are the ones already excluded.

When a budget is exhausted, the outcome is a warning that the check was not performed — never a pass, and
never a validation error attributed to the value.

---

## 2. Bounded integers

### 2.1 The interoperable range

```
MAX_EXACT_INT =  9007199254740991   (2^53 − 1)
MIN_EXACT_INT = -9007199254740991   (−(2^53 − 1))
```

These are the baseline's constants, and the range is not a Python limitation: it is the set of integers every
party to a settings document can hold exactly — the baseline validator, a JSON transport, a browser-side
client, and Dart compiled for the Web. `SPEC.md` amendment 25 fixes it as the default interoperable range.

### 2.2 Inside the range

An integer literal inside the range decodes to a Dart `int` and behaves identically on every platform. Bounds,
defaults, enum members and comparisons are exact.

### 2.3 Beyond the range

A value outside the range is **never silently rounded** (`SPEC.md` amendment 25). Three rules follow:

1. **The source text is authoritative.** The concrete syntax tree keeps the number token verbatim, so parsing,
   editing and writing a document reproduce its bytes whatever the platform or the magnitude. A huge
   integer survives a round trip even where no native integer type could hold it.
2. **The decoded value stays exact.** A literal outside the range decodes to `BigInt`, which is exact on
   native and on Web alike. The choice is made by comparing the literal against the range, never by asking
   whether the platform's `int` accepted it — see §2.4.
3. **Validation refuses it for `int`.** An `int`-typed node holding a value outside the range is reported
   as a validation issue with rule `exact_range` under `VALIDATION_ERROR`, as the baseline does. The same
   bound applies to environment substitution: `env.convert: int` of an out-of-range value
   produces the `env_conversion` issue and no value, rather than a rounded one.

Supporting values beyond the range as ordinary data would be an explicit lossless extension, which
`SPEC.md` amendment 25 keeps out of the default profile. Nothing in the current profile
offers it, and nothing rounds on the way past the check.

Non-finite numbers are a related but separate case: the literals `Infinity`, `-Infinity` and `NaN` are rejected
by the parser with `PARSE_ERROR`, because the baseline rejects them and a document must load in both
implementations. A decimal literal that overflows to infinity, such as `1e400`, does decode to a non-finite
value, and `SPEC.md` amendment 3 forbids a non-finite number from reaching ordinary JSON transport without an
explicitly agreed representation: it may live in the document, and it must be refused or specially
encoded before it leaves it.

### 2.4 Native and Web are not the same machine

Measured with the Dart 3.13 SDK, comparing the same source compiled for the VM and for the Web (dart2js):

| Expression | Native VM | Web |
|---|---|---|
| `int.tryParse('9007199254740993')` | `9007199254740993` | `9007199254740992` — rounded, and reported as a success |
| `int.tryParse('9223372036854775807')` | `9223372036854775807` | `9223372036854776000` — rounded |
| `int.tryParse('123456789012345678901234567890')` | `null` | `1.2345678901234568e+29` — not an integer at all |
| `BigInt.parse(text)` | exact | exact |
| a literal such as `9007199254740993` in source | compiles | does not compile: "can't be represented exactly in JavaScript" |

The reason is that `int` on the VM is a 64-bit signed integer, while `int` on the Web is a JavaScript
number — an IEEE-754 double, exact only to `±(2^53 − 1)`.

Two consequences fix the policy:

- **A successful `int.tryParse` proves nothing about exactness.** On the Web it returns a rounded value for
  every literal above `2^53`, so "did it parse into an `int`" is not a portable test for "can this value be
  held exactly". The decision is made against `MIN_EXACT_INT`/`MAX_EXACT_INT` and the decimal
  text, which is why §2.3 rule 2 is written that way.
- **`int` is not one type.** Code that must behave the same on both platforms treats
  `int` as exact only inside the interoperable range and uses `BigInt` beyond it.

**Implementation status.** The parser keeps the raw token and decodes to `BigInt` when the platform `int` refuses
the literal, which is exact on native and matches the corpus case `huge_integers`. The
platform-independent range test described above is not yet applied, so on Web a literal between `2^53` and
`2^63` still decodes to a rounded `int` instead of a `BigInt`. Closing that gap is a parser change with a
Web-compiled regression test; it is recorded as an open finding in the stage-1 progress notes rather
than presented here as behavior that already holds.

---

## References

- `SPEC.md` amendment 5 (portable descriptor constructs, `pattern`, `key_pattern`), amendment 25 (exact
  integer safety across native, Web and Python), amendment 26 (stable codes, the limits profile, the
  regex-dialect restrictions), amendment 3 (source preservation, non-finite numbers).
- `SPEC_.md` amendment 38: a baseline defect is corrected and reported, never reproduced.
- `fixtures/BASELINE` and `fixtures/python_compat/`: the executed baseline that pins the behavior described here.
