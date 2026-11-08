/// A geographic position in decimal degrees.
///
/// North latitudes and east longitudes are positive.
class LatLng {
  const LatLng(this.lat, this.lon);

  /// Latitude in degrees, -90 to 90.
  final double lat;

  /// Longitude in degrees, -180 to 180.
  final double lon;

  /// True if both values are the same within [toleranceDeg] degrees.
  /// The default tolerance is about 1.5 cm.
  bool closeTo(LatLng other, {double toleranceDeg = 1e-7}) =>
      (lat - other.lat).abs() <= toleranceDeg &&
      _lonDiff(lon, other.lon).abs() <= toleranceDeg;

  static double _lonDiff(double a, double b) {
    var d = a - b;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() =>
      'LatLng(${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)})';
}
