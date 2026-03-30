import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/chat_message.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/tracking_alert.dart';
import '../models/tracking_analytics.dart';
import '../models/visit_evidence.dart';
import '../models/work_zone.dart';
import 'tracking_repository.dart';

class FirebaseTrackingRepository implements TrackingRepository {
  FirebaseTrackingRepository(this._firestore, [FirebaseStorage? storage])
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _firestore.collection('employees');

  CollectionReference<Map<String, dynamic>> get _workZonesRef =>
      _firestore.collection('work_zones');

  CollectionReference<Map<String, dynamic>> get _alertsRef =>
      _firestore.collection('tracking_alerts');

  DocumentReference<Map<String, dynamic>> get _adminConfigRef =>
      _firestore.collection('app_config').doc('admin_security');

  @override
  Future<EmployeeStatus> upsertEmployeeProfile({
    required String employeeName,
    required String phoneNumber,
  }) async {
    final normalizedPhone = _normalizePhone(phoneNumber);
    final now = DateTime.now();
    final docRef = _employeesRef.doc(normalizedPhone);
    final existing = await docRef.get();

    await docRef.set({
      'employeeName': employeeName,
      'phoneNumber': phoneNumber,
      'phoneNumberNormalized': normalizedPhone,
      'lastSeen': Timestamp.fromDate(now),
      if (!existing.exists) ...{
        'isCheckedIn': false,
        'isOnline': false,
        'totalDistanceMeters': 0.0,
      },
    }, SetOptions(merge: true));

    final saved = await docRef.get();
    return _employeeFromDoc(saved);
  }

  @override
  Future<bool> validateAdminPassword(String password) async {
    final doc = await _adminConfigRef.get();
    if (!doc.exists) {
      return false;
    }

    final saved = doc.data()?['adminPassword'] as String?;
    if (saved == null || saved.isEmpty) return false;
    return saved == password;
  }

  CollectionReference<Map<String, dynamic>> _routesRef(String employeeId) {
    return _routeDayRef(employeeId, DateTime.now());
  }

  CollectionReference<Map<String, dynamic>> _routeDayRef(
    String employeeId,
    DateTime date,
  ) {
    return _employeesRef
        .doc(employeeId)
        .collection('routes')
        .doc(_dayId(date))
        .collection('points');
  }

  CollectionReference<Map<String, dynamic>> _visitEvidenceRef(
    String employeeId,
  ) {
    return _employeesRef.doc(employeeId).collection('visit_evidence');
  }

  CollectionReference<Map<String, dynamic>> _chatMessagesRef(
    String employeeId,
  ) {
    return _employeesRef.doc(employeeId).collection('chat_messages');
  }

  @override
  Stream<List<EmployeeStatus>> watchEmployees() {
    return _employeesRef.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => _employeeFromDoc(doc)).toList()
        ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      return list;
    });
  }

  @override
  Stream<EmployeeStatus?> watchEmployee(String employeeId) {
    return _employeesRef.doc(employeeId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return _employeeFromDoc(doc);
    });
  }

  @override
  Stream<List<RoutePoint>> watchTodayRoute(String employeeId) {
    return watchRouteForDate(employeeId, DateTime.now());
  }

  @override
  Stream<List<RoutePoint>> watchRouteForDate(String employeeId, DateTime date) {
    return _routeDayRef(
      employeeId,
      date,
    ).orderBy('timestamp', descending: false).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => _routeFromDoc(employeeId, doc))
          .toList();
    });
  }

  @override
  Future<List<RoutePoint>> getRouteForDate(
    String employeeId,
    DateTime date,
  ) async {
    final snapshot = await _routeDayRef(
      employeeId,
      date,
    ).orderBy('timestamp', descending: false).get();
    return snapshot.docs.map((doc) => _routeFromDoc(employeeId, doc)).toList();
  }

  @override
  Stream<List<WorkZone>> watchWorkZones() {
    return _workZonesRef.orderBy('updatedAt', descending: true).snapshots().map(
      (snapshot) {
        return snapshot.docs
            .map(_workZoneFromDoc)
            .where((zone) => zone.isActive)
            .toList(growable: false);
      },
    );
  }

  @override
  Stream<List<TrackingAlert>> watchTrackingAlerts({
    String? employeeId,
    int limit = 100,
  }) {
    return _alertsRef
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final alerts = snapshot.docs.map(_trackingAlertFromDoc);
          if (employeeId == null) {
            return alerts.toList(growable: false);
          }
          return alerts
              .where((alert) => alert.employeeId == employeeId)
              .toList(growable: false);
        });
  }

  @override
  Future<DailyTrackingReport> buildDailyTrackingReport({
    required String employeeId,
    required DateTime date,
  }) async {
    final employee = await getEmployee(employeeId);
    final points = await getRouteForDate(employeeId, date);
    final totalDistance = _totalDistance(points);
    final dwell = await _calculateDwellPeriods(employeeId, points);
    final activeDuration = points.length > 1
        ? points.last.timestamp.difference(points.first.timestamp)
        : Duration.zero;

    return DailyTrackingReport(
      employeeId: employeeId,
      employeeName: employee?.employeeName ?? 'Employee',
      date: DateTime(date.year, date.month, date.day),
      points: points,
      totalDistanceMeters: totalDistance,
      dwellPeriods: dwell,
      activeDuration: activeDuration,
    );
  }

  @override
  Future<void> saveWorkZone(WorkZone zone) async {
    final zoneRef = zone.id.isEmpty
        ? _workZonesRef.doc()
        : _workZonesRef.doc(zone.id);
    final now = DateTime.now();

    await zoneRef.set({
      'name': zone.name,
      'centerLatitude': zone.centerLatitude,
      'centerLongitude': zone.centerLongitude,
      'radiusMeters': zone.radiusMeters,
      'assignedEmployeeIds': zone.assignedEmployeeIds,
      'isActive': zone.isActive,
      'createdAt': Timestamp.fromDate(zone.createdAt ?? now),
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteWorkZone(String zoneId) async {
    await _workZonesRef.doc(zoneId).delete();
  }

  @override
  Stream<List<VisitEvidence>> watchVisitEvidence(String employeeId) {
    return _visitEvidenceRef(employeeId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => _visitEvidenceFromDoc(employeeId, doc))
              .toList(growable: false);
        });
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(String employeeId) {
    return _chatMessagesRef(employeeId)
        .orderBy('timestamp', descending: false)
        .limit(300)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => _chatMessageFromDoc(employeeId, doc))
              .toList(growable: false);
        });
  }

  @override
  Future<EmployeeStatus?> getEmployee(String employeeId) async {
    final doc = await _employeesRef.doc(employeeId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _employeeFromDoc(doc);
  }

  @override
  Future<void> checkIn({required String employeeId}) async {
    final employeeDoc = await _employeesRef.doc(employeeId).get();
    if (!employeeDoc.exists) {
      throw Exception('Employee profile not found. Please login again.');
    }

    final now = DateTime.now();
    await _employeesRef.doc(employeeId).set({
      'employeeId': employeeId,
      'isCheckedIn': true,
      'isOnline': true,
      'lastSeen': Timestamp.fromDate(now),
      'checkInTime': Timestamp.fromDate(now),
      'checkOutTime': null,
      'activeShiftId': now.microsecondsSinceEpoch.toString(),
      'totalDistanceMeters': 0.0,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> checkOut({required String employeeId}) async {
    final now = DateTime.now();
    await _employeesRef.doc(employeeId).set({
      'isCheckedIn': false,
      'isOnline': false,
      'activeShiftId': null,
      'checkOutTime': Timestamp.fromDate(now),
      'lastSeen': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
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
    final now = DateTime.now();
    final employeeSnapshot = await _employeesRef.doc(employeeId).get();
    final employeeData = employeeSnapshot.data() ?? <String, dynamic>{};
    final employeeName =
        (employeeData['employeeName'] as String?) ?? 'Employee';
    final previousZoneIds =
        ((employeeData['currentZoneIds'] as List<dynamic>?) ??
                const <dynamic>[])
            .whereType<String>()
            .toSet();

    final previous = await _routesRef(
      employeeId,
    ).orderBy('timestamp', descending: true).limit(1).get();

    double currentDistance = 0;
    DateTime? previousTimestamp;
    if (previous.docs.isNotEmpty) {
      final data = previous.docs.first.data();
      final previousLat = (data['latitude'] as num?)?.toDouble();
      final previousLng = (data['longitude'] as num?)?.toDouble();
      previousTimestamp = (data['timestamp'] as Timestamp?)?.toDate();
      if (previousLat != null && previousLng != null) {
        currentDistance = _distanceMeters(
          previousLat,
          previousLng,
          latitude,
          longitude,
        );
      }
    }

    if (accuracyMeters != null && accuracyMeters > 60) {
      return;
    }

    // Only persist a new point when there is meaningful movement.
    if (currentDistance < 2 && previousTimestamp != null) {
      return;
    }

    if (previousTimestamp != null) {
      final seconds = now.difference(previousTimestamp).inMilliseconds / 1000;
      if (seconds > 0) {
        final speed = currentDistance / seconds;
        if (speed > 55) {
          // Ignore GPS spikes faster than ~198 km/h.
          return;
        }
      }
    }

    await _routesRef(employeeId).add({
      'employeeId': employeeId,
      'timestamp': Timestamp.fromDate(now),
      'latitude': latitude,
      'longitude': longitude,
      'speedMetersPerSecond': speedMetersPerSecond,
      'accuracyMeters': accuracyMeters,
    });

    final designatedZones = await _getDesignatedZones(employeeId);
    final insideZones = designatedZones
        .where((zone) {
          final distance = _distanceMeters(
            zone.centerLatitude,
            zone.centerLongitude,
            latitude,
            longitude,
          );
          return distance <= zone.radiusMeters;
        })
        .toList(growable: false);

    final insideZoneIds = insideZones.map((zone) => zone.id).toSet();
    final enteredZones = insideZones
        .where((zone) => !previousZoneIds.contains(zone.id))
        .toList(growable: false);
    final exitedZoneIds = previousZoneIds.difference(insideZoneIds);
    final exitedZones = designatedZones
        .where((zone) => exitedZoneIds.contains(zone.id))
        .toList(growable: false);

    final alerts = <TrackingAlert>[];
    for (final zone in enteredZones) {
      alerts.add(
        TrackingAlert(
          id: '',
          employeeId: employeeId,
          employeeName: employeeName,
          type: TrackingAlertType.arrival,
          title: 'Arrival at ${zone.name}',
          message: '$employeeName arrived at ${zone.name}.',
          timestamp: now,
          latitude: latitude,
          longitude: longitude,
          zoneId: zone.id,
          zoneName: zone.name,
        ),
      );
    }
    for (final zone in exitedZones) {
      alerts.add(
        TrackingAlert(
          id: '',
          employeeId: employeeId,
          employeeName: employeeName,
          type: TrackingAlertType.departure,
          title: 'Departure from ${zone.name}',
          message: '$employeeName left ${zone.name}.',
          timestamp: now,
          latitude: latitude,
          longitude: longitude,
          zoneId: zone.id,
          zoneName: zone.name,
        ),
      );
    }
    if (previousZoneIds.isNotEmpty && insideZoneIds.isEmpty) {
      alerts.add(
        TrackingAlert(
          id: '',
          employeeId: employeeId,
          employeeName: employeeName,
          type: TrackingAlertType.outOfZone,
          title: 'Employee left designated area',
          message: '$employeeName is outside all designated work zones.',
          timestamp: now,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    await _firestore.runTransaction((transaction) async {
      final employeeRef = _employeesRef.doc(employeeId);
      final snapshot = await transaction.get(employeeRef);
      final previousDistance =
          ((snapshot.data()?['totalDistanceMeters'] as num?)?.toDouble() ??
          0.0);

      transaction.set(employeeRef, {
        'latitude': latitude,
        'longitude': longitude,
        'isOnline': isOnline,
        'lastSeen': Timestamp.fromDate(now),
        'totalDistanceMeters': previousDistance + currentDistance,
        'currentZoneIds': insideZoneIds.toList(),
      }, SetOptions(merge: true));
    });

    for (final alert in alerts) {
      await _alertsRef.add({
        'employeeId': alert.employeeId,
        'employeeName': alert.employeeName,
        'type': alert.type.name,
        'title': alert.title,
        'message': alert.message,
        'timestamp': Timestamp.fromDate(alert.timestamp),
        'latitude': alert.latitude,
        'longitude': alert.longitude,
        'zoneId': alert.zoneId,
        'zoneName': alert.zoneName,
      });
    }
  }

  @override
  Future<void> updatePresence({
    required String employeeId,
    required bool isOnline,
  }) async {
    await _employeesRef.doc(employeeId).set({
      'isOnline': isOnline,
      'lastSeen': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
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
    final now = DateTime.now();
    final evidenceRef = _visitEvidenceRef(employeeId).doc();
    final storageRef = _storage
        .ref()
        .child('visit_evidence')
        .child(employeeId)
        .child(_todayId())
        .child('${evidenceRef.id}.jpg');

    await storageRef.putData(
      Uint8List.fromList(photoBytes),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final downloadUrl = await storageRef.getDownloadURL();

    await evidenceRef.set({
      'employeeId': employeeId,
      'type': type.name,
      'remarks': remarks,
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'photoUrl': downloadUrl,
      'timestamp': Timestamp.fromDate(now),
    });
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

    await _chatMessagesRef(employeeId).add({
      'employeeId': employeeId,
      'senderRole': senderRole.name,
      'senderName': senderName,
      'text': trimmed,
      'timestamp': Timestamp.fromDate(DateTime.now()),
    });
  }

  EmployeeStatus _employeeFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return EmployeeStatus(
      employeeId: (data['employeeId'] as String?) ?? doc.id,
      employeeName: (data['employeeName'] as String?) ?? 'Employee',
      phoneNumber: data['phoneNumber'] as String?,
      isCheckedIn: (data['isCheckedIn'] as bool?) ?? false,
      isOnline: (data['isOnline'] as bool?) ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      totalDistanceMeters:
          (data['totalDistanceMeters'] as num?)?.toDouble() ?? 0,
      activeShiftId: data['activeShiftId'] as String?,
      checkInTime: (data['checkInTime'] as Timestamp?)?.toDate(),
      checkOutTime: (data['checkOutTime'] as Timestamp?)?.toDate(),
    );
  }

  RoutePoint _routeFromDoc(
    String employeeId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return RoutePoint(
      employeeId: employeeId,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      speedMetersPerSecond: (data['speedMetersPerSecond'] as num?)?.toDouble(),
    );
  }

  VisitEvidence _visitEvidenceFromDoc(
    String employeeId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final typeRaw = (data['type'] as String?) ?? VisitEvidenceType.place.name;
    final type = typeRaw == VisitEvidenceType.person.name
        ? VisitEvidenceType.person
        : VisitEvidenceType.place;

    return VisitEvidence(
      id: doc.id,
      employeeId: employeeId,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      locationName:
          (data['locationName'] as String?) ??
          '${((data['latitude'] as num?)?.toDouble() ?? 0).toStringAsFixed(5)}, ${((data['longitude'] as num?)?.toDouble() ?? 0).toStringAsFixed(5)}',
      remarks: (data['remarks'] as String?) ?? '',
      type: type,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  ChatMessage _chatMessageFromDoc(
    String employeeId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final roleRaw =
        (data['senderRole'] as String?) ?? ChatSenderRole.employee.name;
    final senderRole = roleRaw == ChatSenderRole.admin.name
        ? ChatSenderRole.admin
        : ChatSenderRole.employee;

    return ChatMessage(
      id: doc.id,
      employeeId: employeeId,
      senderRole: senderRole,
      text: (data['text'] as String?) ?? '',
      senderName: data['senderName'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  WorkZone _workZoneFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return WorkZone(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Zone',
      centerLatitude: (data['centerLatitude'] as num?)?.toDouble() ?? 0,
      centerLongitude: (data['centerLongitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? 150,
      assignedEmployeeIds:
          ((data['assignedEmployeeIds'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  TrackingAlert _trackingAlertFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final typeRaw = (data['type'] as String?) ?? TrackingAlertType.arrival.name;
    final type = switch (typeRaw) {
      'departure' => TrackingAlertType.departure,
      'outOfZone' => TrackingAlertType.outOfZone,
      _ => TrackingAlertType.arrival,
    };

    return TrackingAlert(
      id: doc.id,
      employeeId: (data['employeeId'] as String?) ?? '',
      employeeName: (data['employeeName'] as String?) ?? 'Employee',
      type: type,
      title: (data['title'] as String?) ?? 'Tracking Alert',
      message: (data['message'] as String?) ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      zoneId: data['zoneId'] as String?,
      zoneName: data['zoneName'] as String?,
    );
  }

  Future<List<WorkZone>> _getDesignatedZones(String employeeId) async {
    final snapshot = await _workZonesRef
        .where('isActive', isEqualTo: true)
        .get();
    final zones = snapshot.docs.map(_workZoneFromDoc);
    return zones
        .where((zone) {
          if (zone.assignedEmployeeIds.isEmpty) {
            return true;
          }
          return zone.assignedEmployeeIds.contains(employeeId);
        })
        .toList(growable: false);
  }

  double _totalDistance(List<RoutePoint> points) {
    if (points.length < 2) return 0;

    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += _distanceMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  Future<List<DwellPeriod>> _calculateDwellPeriods(
    String employeeId,
    List<RoutePoint> points,
  ) async {
    if (points.length < 2) return const <DwellPeriod>[];

    const radiusMeters = 70.0;
    const minDwell = Duration(minutes: 8);
    final designatedZones = await _getDesignatedZones(employeeId);
    final dwell = <DwellPeriod>[];

    var segmentStart = 0;
    for (var i = 1; i < points.length; i++) {
      final anchor = points[segmentStart];
      final current = points[i];
      final distance = _distanceMeters(
        anchor.latitude,
        anchor.longitude,
        current.latitude,
        current.longitude,
      );
      if (distance <= radiusMeters) {
        continue;
      }

      final segment = points.sublist(segmentStart, i);
      final period = _segmentToDwell(segment, minDwell, designatedZones);
      if (period != null) {
        dwell.add(period);
      }
      segmentStart = i;
    }

    final finalSegment = points.sublist(segmentStart);
    final finalPeriod = _segmentToDwell(
      finalSegment,
      minDwell,
      designatedZones,
    );
    if (finalPeriod != null) {
      dwell.add(finalPeriod);
    }

    return dwell;
  }

  DwellPeriod? _segmentToDwell(
    List<RoutePoint> segment,
    Duration minDwell,
    List<WorkZone> designatedZones,
  ) {
    if (segment.length < 2) return null;
    final startTime = segment.first.timestamp;
    final endTime = segment.last.timestamp;
    final duration = endTime.difference(startTime);
    if (duration < minDwell) return null;

    final latitude =
        segment.map((point) => point.latitude).reduce((a, b) => a + b) /
        segment.length;
    final longitude =
        segment.map((point) => point.longitude).reduce((a, b) => a + b) /
        segment.length;

    final zone = designatedZones.firstWhere(
      (item) =>
          _distanceMeters(
            item.centerLatitude,
            item.centerLongitude,
            latitude,
            longitude,
          ) <=
          item.radiusMeters,
      orElse: () => const WorkZone(
        id: '',
        name: '',
        centerLatitude: 0,
        centerLongitude: 0,
        radiusMeters: 0,
      ),
    );

    return DwellPeriod(
      startTime: startTime,
      endTime: endTime,
      centerLatitude: latitude,
      centerLongitude: longitude,
      duration: duration,
      zoneName: zone.id.isEmpty ? null : zone.name,
    );
  }

  String _todayId() => _dayId(DateTime.now());

  String _dayId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }
}
