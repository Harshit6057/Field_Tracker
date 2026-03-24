import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/visit_evidence.dart';
import 'tracking_repository.dart';

class FirebaseTrackingRepository implements TrackingRepository {
  FirebaseTrackingRepository(this._firestore, [FirebaseStorage? storage])
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _employeesRef =>
      _firestore.collection('employees');

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
      await _adminConfigRef.set({
        'adminPassword': 'admin123',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return password == 'admin123';
    }

    final saved = doc.data()?['adminPassword'] as String?;
    if (saved == null || saved.isEmpty) {
      await _adminConfigRef.set({
        'adminPassword': 'admin123',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return password == 'admin123';
    }
    return saved == password;
  }

  CollectionReference<Map<String, dynamic>> _routesRef(String employeeId) {
    return _employeesRef
        .doc(employeeId)
        .collection('routes')
        .doc(_todayId())
        .collection('points');
  }

  CollectionReference<Map<String, dynamic>> _visitEvidenceRef(String employeeId) {
    return _employeesRef.doc(employeeId).collection('visit_evidence');
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
    return _routesRef(employeeId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => _routeFromDoc(employeeId, doc)).toList();
    });
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
  Future<EmployeeStatus?> getEmployee(String employeeId) async {
    final doc = await _employeesRef.doc(employeeId).get();
    if (!doc.exists || doc.data() == null) return null;
    return _employeeFromDoc(doc);
  }

  @override
  Future<void> checkIn({
    required String employeeId,
  }) async {
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
    final previous = await _routesRef(employeeId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    double currentDistance = 0;
    DateTime? previousTimestamp;
    if (previous.docs.isNotEmpty) {
      final data = previous.docs.first.data();
      final previousLat = (data['latitude'] as num?)?.toDouble();
      final previousLng = (data['longitude'] as num?)?.toDouble();
      previousTimestamp = (data['timestamp'] as Timestamp?)?.toDate();
      if (previousLat != null && previousLng != null) {
        currentDistance = _distanceMeters(previousLat, previousLng, latitude, longitude);
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

    await _firestore.runTransaction((transaction) async {
      final employeeRef = _employeesRef.doc(employeeId);
      final snapshot = await transaction.get(employeeRef);
      final previousDistance =
          ((snapshot.data()?['totalDistanceMeters'] as num?)?.toDouble() ?? 0.0);

      transaction.set(
        employeeRef,
        {
          'latitude': latitude,
          'longitude': longitude,
          'isOnline': isOnline,
          'lastSeen': Timestamp.fromDate(now),
          'totalDistanceMeters': previousDistance + currentDistance,
        },
        SetOptions(merge: true),
      );
    });
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
      totalDistanceMeters: (data['totalDistanceMeters'] as num?)?.toDouble() ?? 0,
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
      locationName: (data['locationName'] as String?) ??
          '${((data['latitude'] as num?)?.toDouble() ?? 0).toStringAsFixed(5)}, ${((data['longitude'] as num?)?.toDouble() ?? 0).toStringAsFixed(5)}',
      remarks: (data['remarks'] as String?) ?? '',
      type: type,
      photoUrl: data['photoUrl'] as String?,
    );
  }

  String _todayId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }
}
