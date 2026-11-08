/// A small OpenAir file with some problems, for the "Load an example"
/// button.
const String exampleName = 'example.openair';

/// The text of the example. It has problems on purpose.
const String exampleText = '''
*WRITTEN_BY: OpenAir Validator example
* This example has some problems on purpose.
* The header has no *VERSION line.

AC D
AY CTR
AN Example CTR
AH 4500 ft AMSL
AL GND
DP 46:00:00N 014:00:00E
DP 46:00:00N 014:10:00E
DP 45:55:00N 014:10:00E
DP 45:55:00N 014:00:00E

AC Q
AY Q
AN Example danger area
AA MON-FRI 07:00Z/15:00Z
AA EXCEPT 2026-12-25
AH FL95
AL 1000 FT AMSL
V X=46:10:00N 014:30:00E
DC 2.5

AC X
AN Example with an unknown class
AH FL65
AL FL95
DP 46:20:00N 014:00:00E
DP 46:20:00N 014:10:00E
DP 46:15:00N 014:10:00E
DP 46:20:00N 014:00:00E
''';
