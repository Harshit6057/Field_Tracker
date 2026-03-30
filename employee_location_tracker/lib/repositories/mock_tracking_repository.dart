import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/chat_message.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/tracking_alert.dart';
import '../models/tracking_analytics.dart';
import '../models/visit_evidence.dart';
import '../models/work_zone.dart';
import 'tracking_repository.dart';

class MockTrackingRepository implements TrackingRepository {
  MockTrackingRepository() {
    _broadcast();
  }

  final Map<String, EmployeeStatus> _employees = {};
  final Map<String, List<RoutePoint>> _todayRoutes = {};
  final Map<String, List<VisitEvidence>> _visitEvidence = {};
  final Map<String, List<ChatMessage>> _chatMessages = {};
  final Map<String, WorkZone> _zones = {};
  final List<TrackingAlert> _alerts = [];
  final Map<String, Set<String>> _lastInsideZoneIdsByEmployee = {};

  final StreamController<List<EmployeeStatus>> _employeesController =
      StreamController<List<EmployeeStatus>>.broadcast();
  final Map<String, StreamController<EmployeeStatus?>> _employeeControllers =
      {};
  final Map<String, StreamController<List<RoutePoint>>> _routeControllers = {};
  final Map<String, StreamController<List<VisitEvidence>>>
  _visitEvidenceControllers = {};
  final Map<String, StreamController<List<ChatMessage>>> _chatControllers = {};
  final StreamController<List<WorkZone>> _zoneController =
      StreamController<List<WorkZone>>.broadcast();
  final StreamController<List<TrackingAlert>> _alertsController =
      StreamController<List<TrackingAlert>>.broadcast();

  @override
  Future<EmployeeStatus> upsertEmployeeProfile({
    required String employeeName,
    required String phoneNumber,
  }) async {
    final employeeId = _normalizePhone(phoneNumber);
    final now = DateTime.now();

    final existing = _employees[employeeId];
    final profile =
        (existing ??
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
    const configuredPasscode = String.fromEnvironment('MOCK_ADMIN_PASSCODE');
    return configuredPasscode.isNotEmpty && password == configuredPasscode;
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
    yield* watchRouteForDate(employeeId, DateTime.now());
  }

  @override
  Stream<List<RoutePoint>> watchRouteForDate(
    String employeeId,
    DateTime date,
  ) async* {
    final controller = _routeControllers.putIfAbsent(
      employeeId,
      () => StreamController<List<RoutePoint>>.broadcast(),
    );
    yield List.unmodifiable(_todayRoutes[employeeId] ?? []);
    yield* controller.stream;
  }

  @override
  Future<List<RoutePoint>> getRouteForDate(
    String employeeId,
    DateTime date,
  ) async {
    return List.unmodifiable(_todayRoutes[employeeId] ?? const <RoutePoint>[]);
  }

  @override
  Stream<List<VisitEvidence>> watchVisitEvidence(String employeeId) async* {
    final controller = _visitEvidenceControllers.putIfAbsent(
      employeeId,
      () => StreamController<List<VisitEvidence>>.broadcast(),
    );
    yield List.unmodifiable(_visitEvidence[employeeId] ?? []);
    yield* controller.stream;
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(String employeeId) async* {
    final controller = _chatControllers.putIfAbsent(
      employeeId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    yield List.unmodifiable(_chatMessages[employeeId] ?? []);
    yield* controller.stream;
  }

  @override
  Stream<List<WorkZone>> watchWorkZones() async* {
    yield _zones.values.where((zone) => zone.isActive).toList(growable: false);
    yield* _zoneController.stream;
  }

  @override
  Stream<List<TrackingAlert>> watchTrackingAlerts({
    String? employeeId,
    int limit = 100,
  }) async* {
    List<TrackingAlert> current() {
      final list = employeeId == null
          ? _alerts
          : _alerts.where((alert) => alert.employeeId == employeeId).toList();
      return list.take(limit).toList(growable: false);
    }

    yield current();
    yield* _alertsController.stream.map((_) => current());
  }

  @override
  Future<EmployeeStatus?> getEmployee(String employeeId) async {
    return _employees[employeeId];
  }

  @override
  Future<DailyTrackingReport> buildDailyTrackingReport({
    required String employeeId,
    required DateTime date,
  }) async {
    final points = await getRouteForDate(employeeId, date);
    final employee = await getEmployee(employeeId);
    final totalDistanceMeters = _calculateDistance(points);
    final dwellPeriods = _calculateDwell(points);

    return DailyTrackingReport(
      employeeId: employeeId,
      employeeName: employee?.employeeName ?? 'Employee',
      date: DateTime(date.year, date.month, date.day),
      points: points,
      totalDistanceMeters: totalDistanceMeters,
      dwellPeriods: dwellPeriods,
      activeDuration: points.length > 1
          ? points.last.timestamp.difference(points.first.timestamp)
          : Duration.zero,
    );
  }

  @override
  Future<void> saveWorkZone(WorkZone zone) async {
    final id = zone.id.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : zone.id;
    _zones[id] = zone.copyWith(
      id: id,
      createdAt: zone.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _zoneController.add(
      _zones.values.where((item) => item.isActive).toList(growable: false),
    );
  }

  @override
  Future<void> deleteWorkZone(String zoneId) async {
    _zones.remove(zoneId);
    _zoneController.add(
      _zones.values.where((item) => item.isActive).toList(growable: false),
    );
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
    _lastInsideZoneIdsByEmployee[employeeId] = <String>{};
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
    _lastInsideZoneIdsByEmployee.remove(employeeId);
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

    _emitZoneAlerts(
      employee: _employees[employeeId]!,
      latitude: latitude,
      longitude: longitude,
      timestamp: now,
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

  @override
  Future<void> addVisitEvidence({
    required String employeeId,
    required VisitEvidenceType type,
    required String remarks,
    required double latitude,
    required double longitude,
    required String locationName,
    required List<int> photoBytes,
  }) async {
    final evidence = VisitEvidence(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      employeeId: employeeId,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      remarks: remarks,
      type: type,
      localPhotoBytes: Uint8List.fromList(photoBytes),
    );

    final list = _visitEvidence.putIfAbsent(employeeId, () => []);
    list.insert(0, evidence);
    _broadcast();
  }

  @override
  Future<void> sendChatMessage({
    required String employeeId,
    required ChatSenderRole senderRole,
    required String text,
    String? senderName,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final list = _chatMessages.putIfAbsent(employeeId, () => []);
    list.add(
      ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        employeeId: employeeId,
        senderRole: senderRole,
        text: trimmed,
        senderName: senderName,
        timestamp: DateTime.now(),
      ),
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
    for (final entry in _visitEvidenceControllers.entries) {
      entry.value.add(List.unmodifiable(_visitEvidence[entry.key] ?? []));
    }
    for (final entry in _chatControllers.entries) {
      entry.value.add(List.unmodifiable(_chatMessages[entry.key] ?? []));
    }
    _zoneController.add(
      _zones.values.where((item) => item.isActive).toList(growable: false),
    );
    _alertsController.add(List.unmodifiable(_alerts));
  }

  List<EmployeeStatus> _sortedEmployees() {
    final employees = _employees.values.toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return List.unmodifiable(employees);
  }

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
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

  double _calculateDistance(List<RoutePoint> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _haversineMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  List<DwellPeriod> _calculateDwell(List<RoutePoint> points) {
    if (points.length < 2) return const <DwellPeriod>[];

    const radiusMeters = 70.0;
    const minDwell = Duration(minutes: 8);
    final dwell = <DwellPeriod>[];
    var segmentStart = 0;

    for (var i = 1; i < points.length; i++) {
      final anchor = points[segmentStart];
      final point = points[i];
      final distance = _haversineMeters(
        anchor.latitude,
        anchor.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance <= radiusMeters) {
        continue;
      }

      final segment = points.sublist(segmentStart, i);
      final period = _toDwellPeriod(segment, minDwell);
      if (period != null) {
        dwell.add(period);
      }
      segmentStart = i;
    }

    final tail = _toDwellPeriod(points.sublist(segmentStart), minDwell);
    if (tail != null) {
      dwell.add(tail);
    }
    return dwell;
  }

  DwellPeriod? _toDwellPeriod(List<RoutePoint> segment, Duration minDwell) {
    if (segment.length < 2) return null;
    final start = segment.first.timestamp;
    final end = segment.last.timestamp;
    final duration = end.difference(start);
    if (duration < minDwell) return null;

    final centerLatitude =
        segment.map((item) => item.latitude).reduce((a, b) => a + b) /
        segment.length;
    final centerLongitude =
        segment.map((item) => item.longitude).reduce((a, b) => a + b) /
        segment.length;

    return DwellPeriod(
      startTime: start,
      endTime: end,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      duration: duration,
    );
  }

  void _emitZoneAlerts({
    required EmployeeStatus employee,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) {
    final designated = _zones.values
        .where((zone) {
          if (!zone.isActive) return false;
          if (zone.assignedEmployeeIds.isEmpty) return true;
          return zone.assignedEmployeeIds.contains(employee.employeeId);
        })
        .toList(growable: false);

    if (designated.isEmpty) return;

    final inside = designated
        .where((zone) {
          final distance = _haversineMeters(
            zone.centerLatitude,
            zone.centerLongitude,
            latitude,
            longitude,
          );
          return distance <= zone.radiusMeters;
        })
        .map((item) => item.id)
        .toSet();

    final previous =
        _lastInsideZoneIdsByEmployee[employee.employeeId] ?? <String>{};
    final entered = inside.difference(previous);
    final exited = previous.difference(inside);

    for (final zoneId in entered) {
      final zone = _zones[zoneId];
      if (zone == null) continue;
      _alerts.insert(
        0,
        TrackingAlert(
          id: '${timestamp.microsecondsSinceEpoch}-$zoneId-a',
          employeeId: employee.employeeId,
          employeeName: employee.employeeName,
          type: TrackingAlertType.arrival,
          title: 'Arrival at ${zone.name}',
          message: '${employee.employeeName} arrived at ${zone.name}.',
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          zoneId: zone.id,
          zoneName: zone.name,
        ),
      );
    }
    for (final zoneId in exited) {
      final zone = _zones[zoneId];
      if (zone == null) continue;
      _alerts.insert(
        0,
        TrackingAlert(
          id: '${timestamp.microsecondsSinceEpoch}-$zoneId-d',
          employeeId: employee.employeeId,
          employeeName: employee.employeeName,
          type: TrackingAlertType.departure,
          title: 'Departure from ${zone.name}',
          message: '${employee.employeeName} left ${zone.name}.',
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          zoneId: zone.id,
          zoneName: zone.name,
        ),
      );
    }
    if (previous.isNotEmpty && inside.isEmpty) {
      _alerts.insert(
        0,
        TrackingAlert(
          id: '${timestamp.microsecondsSinceEpoch}-out',
          employeeId: employee.employeeId,
          employeeName: employee.employeeName,
          type: TrackingAlertType.outOfZone,
          title: 'Employee left designated area',
          message: '${employee.employeeName} is outside all designated zones.',
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    _lastInsideZoneIdsByEmployee[employee.employeeId] = inside;
  }
}
