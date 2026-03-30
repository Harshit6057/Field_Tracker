class EmployeeStatus {
  const EmployeeStatus({
    required this.employeeId,
    required this.employeeName,
    this.phoneNumber,
    required this.isCheckedIn,
    required this.isOnline,
    required this.lastSeen,
    this.latitude,
    this.longitude,
    this.totalDistanceMeters = 0,
    this.activeShiftId,
    this.checkInTime,
    this.checkOutTime,
      this.department = 'Unassigned',
      this.team = 'General',
  });

  final String employeeId;
  final String employeeName;
  final String? phoneNumber;
  final bool isCheckedIn;
  final bool isOnline;
  final DateTime lastSeen;
  final double? latitude;
  final double? longitude;
  final double totalDistanceMeters;
  final String? activeShiftId;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
    final String department;
    final String team;

  EmployeeStatus copyWith({
    String? employeeId,
    String? employeeName,
    String? phoneNumber,
    bool? isCheckedIn,
    bool? isOnline,
    DateTime? lastSeen,
    double? latitude,
    double? longitude,
    double? totalDistanceMeters,
    String? activeShiftId,
    DateTime? checkInTime,
    DateTime? checkOutTime,
      String? department,
      String? team,
  }) {
    return EmployeeStatus(
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isCheckedIn: isCheckedIn ?? this.isCheckedIn,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      activeShiftId: activeShiftId ?? this.activeShiftId,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
        department: department ?? this.department,
        team: team ?? this.team,
    );
  }
}
