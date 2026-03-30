class WorkZone {
  const WorkZone({
    required this.id,
    required this.name,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusMeters,
    this.assignedEmployeeIds = const <String>[],
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusMeters;
  final List<String> assignedEmployeeIds;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkZone copyWith({
    String? id,
    String? name,
    double? centerLatitude,
    double? centerLongitude,
    double? radiusMeters,
    List<String>? assignedEmployeeIds,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkZone(
      id: id ?? this.id,
      name: name ?? this.name,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      assignedEmployeeIds: assignedEmployeeIds ?? this.assignedEmployeeIds,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
