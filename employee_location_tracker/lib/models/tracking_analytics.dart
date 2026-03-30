import 'route_point.dart';

class DwellPeriod {
  const DwellPeriod({
    required this.startTime,
    required this.endTime,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.duration,
    this.zoneName,
  });

  final DateTime startTime;
  final DateTime endTime;
  final double centerLatitude;
  final double centerLongitude;
  final Duration duration;
  final String? zoneName;
}

class DailyTrackingReport {
  const DailyTrackingReport({
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.points,
    required this.totalDistanceMeters,
    required this.dwellPeriods,
    required this.activeDuration,
  });

  final String employeeId;
  final String employeeName;
  final DateTime date;
  final List<RoutePoint> points;
  final double totalDistanceMeters;
  final List<DwellPeriod> dwellPeriods;
  final Duration activeDuration;
}
