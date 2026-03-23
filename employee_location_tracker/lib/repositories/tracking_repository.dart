import '../models/employee_status.dart';
import '../models/route_point.dart';

abstract class TrackingRepository {
  Future<EmployeeStatus> upsertEmployeeProfile({
    required String employeeName,
    required String phoneNumber,
  });
  Future<bool> validateAdminPassword(String password);
  Stream<List<EmployeeStatus>> watchEmployees();
  Stream<EmployeeStatus?> watchEmployee(String employeeId);
  Stream<List<RoutePoint>> watchTodayRoute(String employeeId);
  Future<EmployeeStatus?> getEmployee(String employeeId);
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
  Future<void> updatePresence({required String employeeId, required bool isOnline});
}
