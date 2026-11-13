part of 'validator.dart';

/// Exact numeric semantics for validation.
///
/// The interoperable integer range is `±(2^53 − 1)` (`docs/grammars.md` §2.1):
/// outside it a value stays exact only when held as `BigInt`, and a
/// comparison must not silently round (`SPEC.md` amendment 25).
/// These helpers compare `int`, `BigInt` and `double` without
/// ever coercing an exact integer through a lossy `double`. The
/// executed baseline coerces every numeric equality through `float()`
/// and therefore treats two distinct integers past `2^53` as equal;
/// that collision is corrected here and reported as PENDING-A34
/// (`SPEC_.md` amendment 38).

/// The largest integer every party to a settings document can hold exactly.
final BigInt maxExactInt = BigInt.parse('9007199254740991');

/// The smallest integer every party to a settings document can hold exactly.
final BigInt minExactInt = BigInt.parse('-9007199254740991');

/// Whether [value] is a numeric type the grammar recognizes
/// (never a `bool`, never a string).
bool isNumericValue(Object? value) =>
    value is int || value is BigInt || value is double;

/// Whether [value] is a mathematical integer (no fractional part).
bool isIntegralValue(Object? value) => switch (value) {
      int() => true,
      BigInt() => true,
      final double d => d.isFinite && d == d.truncateToDouble(),
      _ => false,
    };

/// The exact integer value of an integral [value].
///
/// For a finite integral `double` this reconstructs the
/// value from the IEEE-754 mantissa and exponent instead of rounding,
/// so `1e40` is distinguished from `10^40` (they are
/// different numbers).
BigInt toExactBigInt(Object? value) {
  if (value is int) return BigInt.from(value);
  if (value is BigInt) return value;
  if (value is double) {
    assert(value.isFinite && value == value.truncateToDouble(),
        'toExactBigInt needs an integral value');
    return _integralDoubleToBigInt(value);
  }
  throw StateError('not an exact integer: $value');
}

BigInt _integralDoubleToBigInt(double v) {
  if (v == 0) return BigInt.zero;
  final data = ByteData(8)..setFloat64(0, v);
  final bits = data.getUint64(0);
  final negative = (bits >> 63) & 1 == 1;
  final biasedExponent = (bits >> 52) & 0x7FF;
  final fraction = bits & 0xFFFFFFFFFFFFF;
  BigInt mantissa;
  int exponent;
  if (biasedExponent == 0) {
    mantissa = BigInt.from(fraction); // subnormal
    exponent = -1074;
  } else {
    mantissa = BigInt.from(fraction | (1 << 52));
    exponent = biasedExponent - 1075;
  }
  if (negative) mantissa = -mantissa;
  if (exponent >= 0) return mantissa << exponent;
  return mantissa >> -exponent; // exact for an integral double
}

/// Exact ordering between two numeric values across the three Dart numeric
/// types. Never rounds a side through a lossy `double`: a fractional double is
/// ordered against an integer by its floor, and two fractional doubles
/// compare by value.
int compareNumbers(Object? a, Object? b) {
  final aIntegral = isIntegralValue(a);
  final bIntegral = isIntegralValue(b);
  if (aIntegral && bIntegral) {
    return toExactBigInt(a).compareTo(toExactBigInt(b));
  }
  if (aIntegral) return _compareIntegralFractional(a, b);
  if (bIntegral) return -_compareIntegralFractional(b, a);
  // Both are fractional doubles (or NaN). A fractional
  // double is never equal to an integer, and two doubles compare exactly
  // against each other.
  final x = a! as double;
  final y = b! as double;
  if (x.isNaN || y.isNaN) return x.isNaN ? 1 : -1; // keep a total order
  return x.compareTo(y);
}

/// Compares the integral value [integral] with the fractional double
/// [fractional]; positive when `integral > fractional`.
///
/// A fractional double sits strictly between `floor(d)` and `floor(d)+1`, so
/// the integer side is decided against the floor alone
/// — exact even when the integer is a `BigInt` the `double` type cannot name.
int _compareIntegralFractional(Object? integral, Object? fractional) {
  final d = fractional! as double;
  if (d.isNaN) return -1; // integral sorts before NaN, matching the both-double rule
  final floor = BigInt.from(d.truncateToDouble());
  final big = toExactBigInt(integral);
  final byFloor = big.compareTo(floor);
  if (byFloor != 0) return byFloor;
  // The integer equals the floor; the double is
  // strictly greater than its own floor.
  return -1;
}

/// Exact numeric equality with no bool/number coercion and no rounding.
bool numbersEqual(Object? a, Object? b) => compareNumbers(a, b) == 0;

/// Whether an integer-valued [value] is inside the
/// interoperable exact range (`docs/grammars.md` §2.3 rule 3).
bool withinExactRange(Object? value) {
  if (!isIntegralValue(value)) return false;
  final asBig = toExactBigInt(value);
  return asBig >= minExactInt && asBig <= maxExactInt;
}
