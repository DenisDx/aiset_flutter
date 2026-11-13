part of 'descriptor.dart';

/// The descriptor revision of [source]: `sha256:` plus the first 32
/// hexadecimal characters of the SHA-256 digest of the source's UTF-8 bytes.
///
/// The scheme is the one the compatibility corpus pins, because a
/// revision is a compare-and-set token: a Flutter client addressing a
/// Python backend must present the value that backend computed for the same
/// bytes. It depends on the source text only, so it is independent of map
/// iteration order and changes whenever the source changes.
String descriptorRevision(String source) =>
    'sha256:${sha256Hex(utf8.encode(source)).substring(0, 32)}';

/// The lowercase hexadecimal SHA-256 digest of [bytes].
///
/// Implemented here rather than taken from a package because `aiset_core`
/// depends on nothing but the Dart SDK (SPEC.md LIB-03).
String sha256Hex(List<int> bytes) {
  final digest = _Sha256()..add(bytes);
  final out = StringBuffer();
  for (final byte in digest.digestBytes()) {
    out.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// A minimal FIPS 180-4 SHA-256 over a byte stream.
final class _Sha256 {
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];


  static const int _mask32 = 0xFFFFFFFF;

  final List<int> _h = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];

  final List<int> _block = [];
  int _lengthBytes = 0;

  /// Feeds [bytes] into the running digest.
  void add(List<int> bytes) {
    _lengthBytes += bytes.length;
    var index = 0;
    while (index < bytes.length) {
      final take = math.min(64 - _block.length, bytes.length - index);
      _block.addAll(bytes.skip(index).take(take));
      index += take;
      if (_block.length == 64) {
        _compress(_block);
        _block.clear();
      }
    }
  }

  /// The 32 digest bytes; the message is padded first.
  List<int> digestBytes() {
    final bitLength = _lengthBytes * 8;
    final padding = <int>[0x80];
    while ((_block.length + padding.length) % 64 != 56) {
      padding.add(0);
    }
    add(padding);
    final tail = List<int>.filled(8, 0);
    for (var i = 0; i < 8; i++) {
      tail[i] = (bitLength >>> ((7 - i) * 8)) & 0xFF;
    }
    add(tail);
    final out = <int>[];
    for (final word in _h) {
      out
        ..add((word >>> 24) & 0xFF)
        ..add((word >>> 16) & 0xFF)
        ..add((word >>> 8) & 0xFF)
        ..add(word & 0xFF);
    }
    return out;
  }

  void _compress(List<int> chunk) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = ((chunk[i * 4] & 0xFF) << 24) |
          ((chunk[i * 4 + 1] & 0xFF) << 16) |
          ((chunk[i * 4 + 2] & 0xFF) << 8) |
          (chunk[i * 4 + 3] & 0xFF);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _mask32;
    }
    var a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    var e = _h[4], f = _h[5], g = _h[6], h = _h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & _mask32 & g);
      final temp1 = (h + s1 + ch + _k[i] + w[i]) & _mask32;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & _mask32;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask32;
    }
    _h[0] = (_h[0] + a) & _mask32;
    _h[1] = (_h[1] + b) & _mask32;
    _h[2] = (_h[2] + c) & _mask32;
    _h[3] = (_h[3] + d) & _mask32;
    _h[4] = (_h[4] + e) & _mask32;
    _h[5] = (_h[5] + f) & _mask32;
    _h[6] = (_h[6] + g) & _mask32;
    _h[7] = (_h[7] + h) & _mask32;
  }

  static int _rotr(int value, int bits) =>
      ((value >>> bits) | (value << (32 - bits))) & _mask32;
}
