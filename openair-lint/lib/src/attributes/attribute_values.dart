/// Values and value checks for the airspace attributes AC, AY, AN, AF, AG
/// and AX. Used by `lib/src/rules/attribute_rules.dart`.
///
/// This file has no dependency on the linter, so a reader (for example
/// Navigator) can also use it.
library;

import 'dart:convert' show utf8;

// ---------------------------------------------------------------------------
// AC: airspace class
// ---------------------------------------------------------------------------

/// The airspace classes that `AC` allows, in upper case.
const List<String> airspaceClasses = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'UNC'];

/// Values that old files use in `AC` for "unclassified". The class is `UNC`.
const Set<String> unclassifiedAliases = {
  'UNCLASSIFIED',
  'UNCL',
  'UNK',
  'UKN',
  'UNKNOWN',
};

// ---------------------------------------------------------------------------
// AY: airspace type
// ---------------------------------------------------------------------------

/// The airspace types that `AY` allows, in upper case, from the table in the
/// specification.
const List<String> airspaceTypes = [
  'ACCSEC',
  'ADIZ',
  'ALERT',
  'ASRA',
  'ATZ',
  'AWY',
  'CTA',
  'CTR',
  'CUSTOM',
  'FIR',
  'FIS',
  'GSEC',
  'HTZ',
  'LTA',
  'MATZ',
  'MTA',
  'MTR',
  'N',
  'NONE',
  'OFR',
  'P',
  'Q',
  'R',
  'RMZ',
  'TFR',
  'TIA',
  'TIZ',
  'TMA',
  'TMZ',
  'TRA',
  'TRAFR',
  'TRZ',
  'TSA',
  'UIR',
  'UTA',
  'VFRR',
  'VFRSEC',
  'WARNING',
];

final Set<String> _airspaceTypeSet = airspaceTypes.toSet();

/// True if [upperValue] is a type from the `AY` table.
bool isAirspaceType(String upperValue) => _airspaceTypeSet.contains(upperValue);

/// Other names that old files use for a type from the `AY` table. The
/// meaning is the same, so the replacement is certain.
const Map<String, String> _typeSynonyms = {
  'RESTRICTED': 'R',
  'DANGER': 'Q',
  'PROHIBITED': 'P',
  'NOTAM': 'N',
  'GS': 'GSEC',
  'GLIDING_SECTOR': 'GSEC',
  'GLIDER_SECTOR': 'GSEC',
  'OVERFLIGHT_RESTRICTION': 'OFR',
  'FIS_SECTOR': 'FIS',
  'VFR_SECTOR': 'VFRSEC',
  'VFR_ROUTE': 'VFRR',
  'ACC_SECTOR': 'ACCSEC',
  'TRAFFIC_INFO_AREA': 'TIA',
  'TRANSPONDER_RECOMMENDED_ZONE': 'TRZ',
  'TRANSPONDER_MANDATORY_ZONE': 'TMZ',
  'RADIO_MANDATORY_ZONE': 'RMZ',
  'AIRWAY': 'AWY',
};

/// Old values with no exact type in the `AY` table, and the type that is
/// probably the closest. The data maintainer must check it.
const Map<String, String> _typeGuesses = {
  // WinPilot: "W" is a wave window, a sector for gliders.
  'W': 'GSEC',
  // WinPilot: "GP" is an area where gliders are prohibited.
  'GP': 'P',
  'MRT': 'MTR',
  'MILITARY': 'MTA',
  'TRAINING': 'TRA',
  'TRANING': 'TRA',
};

/// What a reader should write in place of an unknown type or class value.
class TypeHint {
  const TypeHint(this.type, {required this.certain});

  /// A type from the `AY` table.
  final String type;

  /// True if [type] has the same meaning. False if it is only the closest
  /// type.
  final bool certain;
}

/// The `AY` type for an old or wrong value [upperValue], or null if there is
/// no good type. A value that is already in the `AY` table returns itself.
TypeHint? typeHintFor(String upperValue) {
  if (isAirspaceType(upperValue)) return TypeHint(upperValue, certain: true);
  final synonym = _typeSynonyms[upperValue];
  if (synonym != null) return TypeHint(synonym, certain: true);
  final guess = _typeGuesses[upperValue];
  if (guess != null) return TypeHint(guess, certain: false);
  return null;
}

// ---------------------------------------------------------------------------
// AF: frequency
// ---------------------------------------------------------------------------

/// The lowest frequency of the VHF air band for voice, in kHz (118.000 MHz).
const int airBandLowKhz = 118000;

/// The highest channel of the VHF air band for voice, in kHz
/// (136.990 MHz, the last 8.33 kHz channel).
const int airBandHighKhz = 136990;

/// The last two digits (of the kHz value) that a channel name can have, with
/// 25 kHz and 8.33 kHz channel spacing. For example 118.005, 118.010,
/// 118.015, 118.025 and 118.030 are channel names, but 118.020 is not.
const Set<int> channelNameEndings = {
  0, 5, 10, 15, //
  25, 30, 35, 40, //
  50, 55, 60, 65, //
  75, 80, 85, 90, //
};

/// A frequency as read from an `AF` command.
class FrequencyValue {
  FrequencyValue._(this.text, this.decimals, this.khz, this.mhz);

  /// The text as written, for example `123.30`.
  final String text;

  /// The number of digits after the dot, as written.
  final int decimals;

  /// The value in kHz, if it is a whole number of kHz: 3 or fewer decimals
  /// after the zeros at the end are removed. For example `122.4750` is
  /// 122475 kHz. Otherwise null, for example for `118.0083`.
  final int? khz;

  /// The value in MHz.
  final double mhz;

  /// True if the value is in the VHF air band (118.000 to 136.990 MHz).
  bool get inAirBand => mhz >= 117.9999 && mhz <= 136.9901;

  /// True if [khz] is a channel name with 25 kHz or 8.33 kHz spacing.
  bool get isChannelName =>
      khz != null && channelNameEndings.contains(khz! % 100);

  /// The channel name (in kHz) that pilots set on the radio for this value,
  /// or null if there is no such channel.
  ///
  /// - A value that is a channel name returns itself.
  /// - A value with more than 3 decimals returns the channel whose real
  ///   frequency is within [channelTolerance] kHz of the value. For example
  ///   `118.0083` (the real frequency of an 8.33 kHz channel) returns 118010.
  /// - Other values return null.
  int? get channelKhz {
    if (khz != null) return isChannelName ? khz : null;
    final (name, distance) = nearestChannelByFrequency(mhz * 1000);
    return distance <= channelTolerance ? name : null;
  }

  /// [khz] as text with three decimals, for example `126.100`.
  String get threeDecimals => khz == null ? text : formatKhz(khz!);
}

/// The largest distance (in kHz) between a value with more than 3 decimals
/// and the real frequency of a channel. Within this distance, the value is
/// read as that channel.
const double channelTolerance = 1.0;

final RegExp _plainNumber = RegExp(r'^(\d+)(?:\.(\d+))?$');

/// Reads a plain frequency such as `123.300`. Returns null if [text] is not
/// a plain number with a dot as the decimal separator.
FrequencyValue? parseFrequency(String text) {
  final m = _plainNumber.firstMatch(text);
  if (m == null) return null;
  final whole = m.group(1)!;
  final fraction = m.group(2) ?? '';
  final mhz = double.parse(text);
  // Zeros after the third decimal do not change the value.
  var significant = fraction;
  while (significant.length > 3 && significant.endsWith('0')) {
    significant = significant.substring(0, significant.length - 1);
  }
  int? khz;
  if (significant.length <= 3 && whole.length <= 6) {
    khz = int.parse(whole) * 1000 + int.parse(significant.padRight(3, '0'));
  }
  return FrequencyValue._(text, fraction.length, khz, mhz);
}

/// The channel whose real frequency is nearest to [frequencyKhz], as
/// (channel name in kHz, distance in kHz).
///
/// In each 25 kHz block that starts at `B`, the channel names and their real
/// frequencies are: `B` (25 kHz channel, real frequency `B`), `B+10` (real
/// frequency `B+8.33`) and `B+15` (real frequency `B+16.67`). The 8.33 kHz
/// channel `B+5` has the same real frequency as `B`. This function returns
/// `B` for it.
(int, double) nearestChannelByFrequency(double frequencyKhz) {
  final base = (frequencyKhz / 25).floor() * 25;
  var bestName = base;
  var bestDistance = double.infinity;
  for (final block in [base - 25, base, base + 25]) {
    for (final (offset, name) in [
      (0.0, block),
      (25 / 3, block + 10),
      (50 / 3, block + 15),
    ]) {
      final distance = (frequencyKhz - (block + offset)).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestName = name;
      }
    }
  }
  return (bestName, bestDistance);
}

/// Writes a kHz value as MHz with three decimals, for example `123.300`.
String formatKhz(int khz) =>
    '${khz ~/ 1000}.${(khz % 1000).toString().padLeft(3, '0')}';

/// The closest channel names below and above [khz] (25 kHz or 8.33 kHz
/// spacing).
(int, int) nearestChannelNames(int khz) {
  var low = khz;
  while (!channelNameEndings.contains(low % 100)) {
    low--;
  }
  var high = khz;
  while (!channelNameEndings.contains(high % 100)) {
    high++;
  }
  return (low, high);
}

final RegExp _numberWithComma = RegExp(r'^\d+,\d+$');
final RegExp _numberWithUnit =
    RegExp(r'^(\d+(?:[.,]\d+)?)\s*(MHZ|KHZ|HZ)$', caseSensitive: false);
final RegExp _numberToken = RegExp(r'^\d+(?:[.,]\d+)?$');
final RegExp _numberListToken = RegExp(r'^\d+\.\d+(?:,\d+\.\d+)+$');
final RegExp _tokenSeparator = RegExp(r'[\s/;]+');

/// The numbers in [value] that stand alone, separated by blanks, `/`, `;`
/// or `,`. For example `123.300/124.500` has two numbers, but `1.23e2` has
/// none.
List<String> _separateNumbers(String value) => [
      for (final token in value.split(_tokenSeparator))
        if (_numberToken.hasMatch(token))
          token
        else if (_numberListToken.hasMatch(token))
          ...token.split(',')
    ];

/// The problem with the format of an `AF` value, or null if the value is a
/// plain number with a dot as the decimal separator.
String? frequencyFormatProblem(String value) {
  if (value.isEmpty) {
    return 'AF has no frequency. Write the frequency in MHz, '
        'for example "AF 123.300".';
  }
  if (_plainNumber.hasMatch(value)) return null;
  if (_numberWithComma.hasMatch(value)) {
    final fixed = value.replaceFirst(',', '.');
    return 'Use a dot as the decimal separator: write "AF $fixed", '
        'not "AF $value".';
  }
  final unit = _numberWithUnit.firstMatch(value);
  if (unit != null) {
    final number = unit.group(1)!.replaceFirst(',', '.');
    final isMhz = unit.group(2)!.toUpperCase() == 'MHZ';
    return isMhz
        ? 'Write only the number in MHz, without a unit: "AF $number".'
        : 'Write only the number in MHz, without a unit. '
            'For example "AF 123.300".';
  }
  final numbers = _separateNumbers(value);
  if (numbers.length > 1) {
    final commands = [
      for (final n in numbers) '"AF ${n.replaceFirst(',', '.')}"',
    ];
    final last = commands.removeLast();
    return 'AF must contain one frequency, but "$value" has more than one '
        'number. Write one AF command for each frequency: '
        '${commands.join(', ')} and $last.';
  }
  if (numbers.length == 1 && _plainNumber.hasMatch(numbers.first)) {
    return 'AF must contain only the frequency, but "$value" also has other '
        'text. Write only the number in MHz: "AF ${numbers.first}". Put the '
        'name of the station in AG.';
  }
  return '"$value" is not a frequency. Write the frequency in MHz with a dot '
      'as the decimal separator, for example "AF 123.300".';
}

// ---------------------------------------------------------------------------
// AX: transponder code
// ---------------------------------------------------------------------------

final RegExp _fourDigits = RegExp(r'^[0-9]{4}$');

/// True if [code] is a transponder code with exactly 4 digits, as the
/// specification requires.
bool isFourDigitCode(String code) => _fourDigits.hasMatch(code);

/// Transponder codes for emergencies. An airspace never uses them.
const Map<String, String> emergencyCodes = {
  '7500': 'unlawful interference (hijack)',
  '7600': 'radio failure',
  '7700': 'emergency',
};

// ---------------------------------------------------------------------------
// All attributes
// ---------------------------------------------------------------------------

/// True if [upperArgument] (the argument of [upperKeyword], in upper case)
/// passes the error rules of the attributes group.
///
/// The rule `case-not-upper-case` can use this. When the upper case value
/// is still wrong, the attribute rule already reports the value with a
/// better fix. Then a second error that only asks for upper case is not
/// useful. Keywords other than AC, AY, AF and AX return true.
bool isValidAttributeValue(String upperKeyword, String upperArgument) =>
    switch (upperKeyword) {
      'AC' => airspaceClasses.contains(upperArgument),
      'AY' => isAirspaceType(upperArgument),
      'AF' => frequencyFormatProblem(upperArgument) == null,
      'AX' => isFourDigitCode(upperArgument),
      _ => true,
    };

// ---------------------------------------------------------------------------
// AN, AG: text
// ---------------------------------------------------------------------------

/// Windows-1252 characters for the bytes 0x80 to 0x9F. Text that was decoded
/// with Windows-1252 has these characters in place of the bytes.
const Map<int, int> _cp1252ToByte = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, //
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

int? _asByte(int codeUnit) =>
    codeUnit < 0x100 ? codeUnit : _cp1252ToByte[codeUnit];

/// A part of a text that looks like UTF-8 that was decoded a second time as
/// Latin-1 or Windows-1252, for example `Ã–` in place of `Ö`.
class DoubleEncoding {
  const DoubleEncoding({
    required this.offset,
    required this.end,
    required this.repaired,
  });

  /// The offset of the first wrong character (0-based).
  final int offset;

  /// The offset after the last wrong character.
  final int end;

  /// The whole text with every wrong part repaired.
  final String repaired;
}

/// True if [rune] is a character that names in airspace files use. A
/// repaired double-encoded sequence must give such a character.
///
/// Many correct names have two special characters that also form a valid
/// UTF-8 sequence, for example `Úš` in the Czech name `Úštěk` (the bytes
/// DA 9A give the Arabic letter U+069A). The result of such a pair is not
/// a character that a name uses, so the pair is not double-encoded.
///
/// Accepted: Latin-1 Supplement and Latin Extended-A/B (U+00A0 to U+024F),
/// Greek and Cyrillic (U+0370 to U+04FF), Latin Extended Additional
/// (U+1E00 to U+1EFF), general punctuation (U+2000 to U+206F), the euro
/// sign and the trade mark sign.
bool isPlausibleRepairedChar(int rune) =>
    (rune >= 0x00A0 && rune <= 0x024F) ||
    (rune >= 0x0370 && rune <= 0x04FF) ||
    (rune >= 0x1E00 && rune <= 0x1EFF) ||
    (rune >= 0x2000 && rune <= 0x206F) ||
    rune == 0x20AC ||
    rune == 0x2122;

/// Finds text that was encoded as UTF-8 two times, for example
/// `AUGUSTÃ\u0093W` in place of `AUGUSTÓW`. Returns null if there is none.
///
/// A sequence counts only if the repaired character is a character that
/// names use (see [isPlausibleRepairedChar]).
DoubleEncoding? findDoubleEncoding(String text) {
  int? first;
  var last = 0;
  final out = StringBuffer();
  var i = 0;
  var copied = 0;
  while (i < text.length) {
    final lead = _asByte(text.codeUnitAt(i));
    final count = lead == null
        ? 0
        : lead >= 0xC2 && lead <= 0xDF
            ? 1
            : lead >= 0xE0 && lead <= 0xEF
                ? 2
                : lead >= 0xF0 && lead <= 0xF4
                    ? 3
                    : 0;
    if (count > 0 && i + count < text.length) {
      final bytes = <int>[lead!];
      for (var k = 1; k <= count; k++) {
        final b = _asByte(text.codeUnitAt(i + k));
        if (b == null || b < 0x80 || b > 0xBF) break;
        bytes.add(b);
      }
      if (bytes.length == count + 1) {
        String? decoded;
        try {
          decoded = utf8.decode(bytes);
        } on FormatException {
          decoded = null;
        }
        if (decoded != null && isPlausibleRepairedChar(decoded.runes.first)) {
          first ??= i;
          out.write(text.substring(copied, i));
          out.write(decoded);
          i += count + 1;
          copied = i;
          last = i;
          continue;
        }
      }
    }
    i++;
  }
  if (first == null) return null;
  out.write(text.substring(copied));
  return DoubleEncoding(offset: first, end: last, repaired: out.toString());
}

/// True if [codeUnit] is not printable ASCII (space to `~`).
bool isNonAscii(int codeUnit) => codeUnit > 0x7E;

const String _from = 'ÀÁÂÃÇÈÉÊËÌÍÎÏÑÒÓÔÕÙÚÛÝàáâãçèéêëìíîïñòóôõùúûýÿ'
    'ĀāĂăĄąĆćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİı'
    'ĴĵĶķĹĺĻļĽľĿŀŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧ'
    'ŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžȘșȚțĐđŁłÐð';
const String _to = 'AAAACEEEEIIIINOOOOUUUYaaaaceeeeiiiinoooouuuyy'
    'AaAaAaCcCcCcCcDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIi'
    'JjKkLlLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTtTt'
    'UuUuUuUuUuUuWwYyYZzZzZzSsTtDdLlDd';

const Map<String, String> _multi = {
  'Ä': 'AE', 'Ö': 'OE', 'Ü': 'UE', 'ä': 'ae', 'ö': 'oe', 'ü': 'ue', //
  'ß': 'ss', 'Å': 'AA', 'å': 'aa', 'Æ': 'AE', 'æ': 'ae', 'Ø': 'OE',
  'ø': 'oe', 'Œ': 'OE', 'œ': 'oe', 'Þ': 'TH', 'þ': 'th',
  ' ': ' ', // no-break space
  '–': '-', '—': '-', '‘': "'", '’': "'", '“': '"', '”': '"',
};

final Map<String, String> _simple = {
  for (var i = 0; i < _from.length; i++) _from[i]: _to[i],
  ..._multi,
};

/// [text] with simple ASCII characters in place of special characters,
/// as the specification recommends (for example `ue` for `ü`).
/// Returns null if a character has no simple form (for example Cyrillic).
///
/// An upper case letter with a two-letter replacement keeps the case of the
/// word: `Ölberg` gives `Oelberg`, but `ÖLBERG` gives `OELBERG`.
String? asciiVersion(String text) {
  final out = StringBuffer();
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune <= 0x7E) {
      out.writeCharCode(rune);
      continue;
    }
    var replacement = _simple[String.fromCharCode(rune)];
    if (replacement == null) return null;
    if (replacement.length == 2 &&
        _isUpperCaseLetter(replacement) &&
        i + 1 < runes.length &&
        _isLowerCaseLetter(String.fromCharCode(runes[i + 1]))) {
      replacement = replacement[0] + replacement[1].toLowerCase();
    }
    out.write(replacement);
  }
  return out.toString();
}

bool _isUpperCaseLetter(String s) =>
    s.toUpperCase() == s && s.toLowerCase() != s;

bool _isLowerCaseLetter(String s) =>
    s.toLowerCase() == s && s.toUpperCase() != s;
