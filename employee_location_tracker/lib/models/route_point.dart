class RoutePoint {
  const RoutePoint({
    required this.employeeId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.speedMetersPerSecond,
  });

  final String employeeId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? speedMetersPerSecond;
}
