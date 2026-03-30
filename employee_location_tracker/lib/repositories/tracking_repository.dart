import '../models/chat_message.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/tracking_alert.dart';
import '../models/tracking_analytics.dart';
import '../models/visit_evidence.dart';
import '../models/work_zone.dart';

abstract class TrackingRepository {
  Future<EmployeeStatus> upsertEmployeeProfile({
    required String employeeName,
    required String phoneNumber,
  });
  Future<bool> validateAdminPassword(String password);
  Stream<List<EmployeeStatus>> watchEmployees();
  Stream<EmployeeStatus?> watchEmployee(String employeeId);
  Stream<List<RoutePoint>> watchTodayRoute(String employeeId);
  Stream<List<RoutePoint>> watchRouteForDate(String employeeId, DateTime date);
  Future<List<RoutePoint>> getRouteForDate(String employeeId, DateTime date);
  Stream<List<VisitEvidence>> watchVisitEvidence(String employeeId);
  Stream<List<ChatMessage>> watchChatMessages(String employeeId);
  Stream<List<WorkZone>> watchWorkZones();
  Stream<List<TrackingAlert>> watchTrackingAlerts({
    String? employeeId,
    int limit = 100,
  });
  Future<EmployeeStatus?> getEmployee(String employeeId);
  Future<DailyTrackingReport> buildDailyTrackingReport({
    required String employeeId,
    required DateTime date,
  });
  Future<void> saveWorkZone(WorkZone zone);
  Future<void> deleteWorkZone(String zoneId);
  Future<void> checkIn({required String employeeId});
  Future<void> checkOut({required String employeeId});
  Future<void> updateLocation({
    required String employeeId,
    required double latitude,
    required double longitude,
    required bool isOnline,
    double? speedMetersPerSecond,
    double? accuracyMeters,
  });
  Future<void> updatePresence({
    required String employeeId,
    required bool isOnline,
  });
  Future<void> addVisitEvidence({
    required String employeeId,
    required VisitEvidenceType type,
    required String remarks,
    required double latitude,
    required double longitude,
    required String locationName,
    required List<int> photoBytes,
  });
  Future<void> sendChatMessage({
    required String employeeId,
    required ChatSenderRole senderRole,
    required String text,
    String? senderName,
  });
}
