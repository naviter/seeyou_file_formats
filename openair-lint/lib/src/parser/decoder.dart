import 'dart:convert' show utf8;

import '../model/openair_file.dart' show TextEncoding;

/// One part of the input bytes that is not valid UTF-8.
class InvalidByteSequence {
  const InvalidByteSequence(this.byteOffset, this.bytes, this.textOffset);

  /// Offset of the first bad byte (0-based, counted after a byte order mark).
  final int byteOffset;

  /// The bad bytes.
  final List<int> bytes;

  /// Offset of the U+FFFD replacement character in the decoded text.
  final int textOffset;
}

/// The result of [decodeBytes].
class DecodedText {
  const DecodedText({
    required this.text,
    required this.encoding,
    required this.hasBom,
    required this.invalid,
  });

  /// The decoded text, without the byte order mark.
  final String text;

  /// The detected encoding.
  final TextEncoding encoding;

  /// True if the bytes start with a byte order mark.
  final bool hasBom;

  /// Parts that are not valid UTF-8. Each part is one U+FFFD in [text].
  final List<InvalidByteSequence> invalid;
}

/// Decodes the bytes of a file. It never throws.
///
/// - UTF-8 is the default. A UTF-8 byte order mark (EF BB BF) is removed.
/// - Bytes that are not valid UTF-8 become U+FFFD. Each bad part is listed in
///   [DecodedText.invalid].
/// - A UTF-16 byte order mark (FF FE or FE FF) selects UTF-16. The
///   specification does not allow UTF-16, but the text is still decoded so
///   that the other rules can run.
DecodedText decodeBytes(List<int> bytes) {
  final n = bytes.length;
  if (n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(
      text: _decodeUtf16(bytes, 2, littleEndian: true),
      encoding: TextEncoding.utf16le,
      hasBom: true,
      invalid: const [],
    );
  }
  if (n >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(
      text: _decodeUtf16(bytes, 2, littleEndian: false),
      encoding: TextEncoding.utf16be,
      hasBom: true,
      invalid: const [],
    );
  }
  var start = 0;
  var hasBom = false;
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    start = 3;
    hasBom = true;
  }
  // Fast path: valid UTF-8.
  try {
    final text = utf8.decode(start == 0 ? bytes : bytes.sublist(start));
    return DecodedText(
      text: text,
      encoding: TextEncoding.utf8,
      hasBom: hasBom,
      invalid: const [],
    );
  } on FormatException {
    // Slow path below.
  }
  final buffer = StringBuffer();
  final invalid = <InvalidByteSequence>[];
  var textLength = 0;
  var runStart = start;
  var i = start;

  void flushRun(int end) {
    if (end > runStart) {
      final s = utf8.decode(bytes.sublist(runStart, end));
      buffer.write(s);
      textLength += s.length;
    }
  }

  while (i < n) {
    final b = bytes[i];
    final len = _validSequenceLength(bytes, i, n);
    if (len > 0) {
      i += len;
      continue;
    }
    // Invalid. Find the maximal bad part: the lead byte plus the
    // continuation bytes that were valid so far.
    final badLength = _badSequenceLength(bytes, i, n, b);
    flushRun(i);
    invalid.add(InvalidByteSequence(i - start,
        List<int>.unmodifiable(bytes.sublist(i, i + badLength)), textLength));
    buffer.writeCharCode(0xFFFD);
    textLength += 1;
    i += badLength;
    runStart = i;
  }
  flushRun(n);
  return DecodedText(
    text: buffer.toString(),
    encoding: TextEncoding.utf8,
    hasBom: hasBom,
    invalid: invalid,
  );
}

bool _isCont(int b) => b >= 0x80 && b <= 0xBF;

/// Returns the length of a valid UTF-8 sequence at [i], or 0.
int _validSequenceLength(List<int> bytes, int i, int n) {
  final b = bytes[i];
  if (b < 0x80) return 1;
  if (b >= 0xC2 && b <= 0xDF) {
    return (i + 1 < n && _isCont(bytes[i + 1])) ? 2 : 0;
  }
  if (b >= 0xE0 && b <= 0xEF) {
    if (i + 2 >= n) return 0;
    final b1 = bytes[i + 1];
    final lo = b == 0xE0 ? 0xA0 : 0x80;
    final hi = b == 0xED ? 0x9F : 0xBF;
    if (b1 < lo || b1 > hi) return 0;
    return _isCont(bytes[i + 2]) ? 3 : 0;
  }
  if (b >= 0xF0 && b <= 0xF4) {
    if (i + 3 >= n) return 0;
    final b1 = bytes[i + 1];
    final lo = b == 0xF0 ? 0x90 : 0x80;
    final hi = b == 0xF4 ? 0x8F : 0xBF;
    if (b1 < lo || b1 > hi) return 0;
    return (_isCont(bytes[i + 2]) && _isCont(bytes[i + 3])) ? 4 : 0;
  }
  return 0;
}

/// The number of bytes that form one bad part at [i]: the lead byte plus
/// the continuation bytes that were still valid (the "maximal subpart").
int _badSequenceLength(List<int> bytes, int i, int n, int b) {
  int expected;
  if (b >= 0xC2 && b <= 0xDF) {
    expected = 2;
  } else if (b >= 0xE0 && b <= 0xEF) {
    expected = 3;
  } else if (b >= 0xF0 && b <= 0xF4) {
    expected = 4;
  } else {
    return 1;
  }
  var len = 1;
  while (len < expected && i + len < n) {
    final c = bytes[i + len];
    if (len == 1) {
      final lo = b == 0xE0 ? 0xA0 : (b == 0xF0 ? 0x90 : 0x80);
      final hi = b == 0xED ? 0x9F : (b == 0xF4 ? 0x8F : 0xBF);
      if (c < lo || c > hi) break;
    } else if (!_isCont(c)) {
      break;
    }
    len++;
  }
  return len;
}

String _decodeUtf16(List<int> bytes, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  if ((bytes.length - start).isOdd) units.add(0xFFFD);
  return String.fromCharCodes(units);
}
