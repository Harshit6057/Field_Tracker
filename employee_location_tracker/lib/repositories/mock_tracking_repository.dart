import 'dart:async';
import 'dart:math' as math;

import '../models/employee_status.dart';
import '../models/route_point.dart';
import 'tracking_repository.dart';

class MockTrackingRepository implements TrackingRepository {
  MockTrackingRepository() {
    _broadcast();
  }

  final Map<String, EmployeeStatus> _employees = {};
  final Map<String, List<RoutePoint>> _todayRoutes = {};

  final StreamController<List<EmployeeStatus>> _employeesController =
      StreamController<List<EmployeeStatus>>.broadcast();
  final Map<String, StreamController<EmployeeStatus?>> _employeeControllers = {};
  final Map<String, StreamController<List<RoutePoint>>> _routeControllers = {};

  @override
  Future<EmployeeStatus> upsertEmployeeProfile({
    required String employeeName,
    required String phoneNumber,
  }) async {
    final employeeId = _normalizePhone(phoneNumber);
    final now = DateTime.now();

    final existing = _employees[employeeId];
    final profile = (existing ??
            EmployeeStatus(
              employeeId: employeeId,
              employeeName: employeeName,
              phoneNumber: phoneNumber,
              isCheckedIn: false,
              isOnline: false,
              lastSeen: now,
            ))
        .copyWith(
      employeeName: employeeName,
      phoneNumber: phoneNumber,
      lastSeen: now,
    );

    _employees[employeeId] = profile;
    _broadcast();
    return profile;
  }

  @override
  Future<bool> validateAdminPassword(String password) async {
    return password == 'admin123';
  }

  @override
  Stream<List<EmployeeStatus>> watchEmployees() async* {
    yield _sortedEmployees();
    yield* _employeesController.stream;
  }

  @override
  Stream<EmployeeStatus?> watchEmployee(String employeeId) async* {
    final controller = _employeeControllers.putIfAbsent(
      employeeId,
      () => StreamController<EmployeeStatus?>.broadcast(),
    );
    yield _employees[employeeId];
    yield* controller.stream;
  }

  @override
  Stream<List<RoutePoint>> watchTodayRoute(String employeeId) async* {
    final controller = _routeControllers.putIfAbsent(
      employeeId,
      () => StreamController<List<RoutePoint>>.broadcast(),
    );
    yield List.unmodifiable(_todayRoutes[employeeId] ?? []);
    yield* controller.stream;
  }

  @override
  Future<EmployeeStatus?> getEmployee(String employeeId) async {
    return _employees[employeeId];
  }

  @override
  Future<void> checkIn({required String employeeId}) async {
    final current = _employees[employeeId];
    if (current == null) {
      throw Exception('Employee profile not found.');
    }

    final now = DateTime.now();
    _employees[employeeId] = current.copyWith(
      isCheckedIn: true,
      isOnline: true,
      lastSeen: now,
      checkInTime: now,
      checkOutTime: null,
      totalDistanceMeters: 0,
      activeShiftId: now.microsecondsSinceEpoch.toString(),
    );

    _todayRoutes[employeeId] = [];
    _broadcast();
  }

  @override
  Future<void> checkOut({required String employeeId}) async {
    final current = _employees[employeeId];
    if (current == null) return;

    _employees[employeeId] = current.copyWith(
      isCheckedIn: false,
      isOnline: false,
      activeShiftId: null,
      checkOutTime: DateTime.now(),
      lastSeen: DateTime.now(),
    );
    _broadcast();
  }

  @override
  Future<void> updateLocation({
    required String employeeId,
    required double latitude,
    required double longitude,
    required bool isOnline,
    double? speedMetersPerSecond,
    double? accuracyMeters,
  }) async {
    final current = _employees[employeeId];
    if (current == null) return;

    if (accuracyMeters != null && accuracyMeters > 60) {
      return;
    }

    final route = _todayRoutes.putIfAbsent(employeeId, () => []);
    final now = DateTime.now();
    double segmentDistance = 0;

    if (route.isNotEmpty) {
      final previous = route.last;
      segmentDistance = _haversineMeters(
        previous.latitude,
        previous.longitude,
        latitude,
        longitude,
      );

      final seconds = now.difference(previous.timestamp).inMilliseconds / 1000;
      // Mirror production behavior: no new point unless movement is meaningful.
      if (segmentDistance < 2) {
        return;
      }
      if (seconds > 0 && (segmentDistance / seconds) > 55) {
        return;
      }
    }

    route.add(
      RoutePoint(
        employeeId: employeeId,
        timestamp: now,
        latitude: latitude,
        longitude: longitude,
        speedMetersPerSecond: speedMetersPerSecond,
      ),
    );

    _employees[employeeId] = current.copyWith(
      latitude: latitude,
      longitude: longitude,
      isOnline: isOnline,
      lastSeen: now,
      totalDistanceMeters: current.totalDistanceMeters + segmentDistance,
    );

    _broadcast();
  }

  @override
  Future<void> updatePresence({
    required String employeeId,
    required bool isOnline,
  }) async {
    final current = _employees[employeeId];
    if (current == null) return;

    _employees[employeeId] = current.copyWith(
      isOnline: isOnline,
      lastSeen: DateTime.now(),
    );
    _broadcast();
  }

  void _broadcast() {
    _employeesController.add(_sortedEmployees());

    for (final entry in _employeeControllers.entries) {
      entry.value.add(_employees[entry.key]);
    }
    for (final entry in _routeControllers.entries) {
      entry.value.add(List.unmodifiable(_todayRoutes[entry.key] ?? []));
    }
  }

  List<EmployeeStatus> _sortedEmployees() {
    final employees = _employees.values.toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return List.unmodifiable(employees);
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const radius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radius * c;
  }

  double _degToRad(double value) => value * math.pi / 180;
}
