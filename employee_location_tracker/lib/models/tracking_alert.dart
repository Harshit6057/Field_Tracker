enum TrackingAlertType { arrival, departure, outOfZone }

class TrackingAlert {
  const TrackingAlert({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.zoneId,
    this.zoneName,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final TrackingAlertType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String? zoneId;
  final String? zoneName;

  String get typeLabel {
    switch (type) {
      case TrackingAlertType.arrival:
        return 'Arrival';
      case TrackingAlertType.departure:
        return 'Departure';
      case TrackingAlertType.outOfZone:
        return 'Out Of Zone';
    }
  }
}
