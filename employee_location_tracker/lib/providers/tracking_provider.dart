import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/app_config.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/visit_evidence.dart';
import '../repositories/firebase_tracking_repository.dart';
import '../repositories/mock_tracking_repository.dart';
import '../repositories/tracking_repository.dart';
import '../services/device_tracking_service.dart';
import 'session_provider.dart';

class EmployeeTrackingState {
	const EmployeeTrackingState({
		this.isCheckedIn = false,
		this.isOnline = false,
		this.isLoading = false,
		this.error,
	});

	final bool isCheckedIn;
	final bool isOnline;
	final bool isLoading;
	final String? error;

	EmployeeTrackingState copyWith({
		bool? isCheckedIn,
		bool? isOnline,
		bool? isLoading,
		String? error,
	}) {
		return EmployeeTrackingState(
			isCheckedIn: isCheckedIn ?? this.isCheckedIn,
			isOnline: isOnline ?? this.isOnline,
			isLoading: isLoading ?? this.isLoading,
			error: error,
		);
	}
}

class TrackingController extends StateNotifier<EmployeeTrackingState> {
	TrackingController(this.ref)
			: _repository = ref.read(trackingRepositoryProvider),
				_deviceTracking = DeviceTrackingService(),
				super(const EmployeeTrackingState()) {
		ref.listen<SessionState>(sessionProvider, (previous, next) {
			_syncWithSession(next);
		});
		_syncWithSession(ref.read(sessionProvider));
	}

	final Ref ref;
	final TrackingRepository _repository;
	final DeviceTrackingService _deviceTracking;

	String? _currentEmployeeId;

	Future<void> _syncWithSession(SessionState session) async {
		if (session.role != UserRole.employee || session.employeeId == null) {
			await _deviceTracking.stop();
			_currentEmployeeId = null;
			state = const EmployeeTrackingState();
			return;
		}

		_currentEmployeeId = session.employeeId;
		final employee = await _repository.getEmployee(session.employeeId!);
		if (employee != null) {
			state = state.copyWith(
				isCheckedIn: employee.isCheckedIn,
				isOnline: employee.isOnline,
			);
			if (employee.isCheckedIn) {
				await _startTracking();
			}
		}
	}

	Future<void> checkIn() async {
		final employeeId = _currentEmployeeId;
		if (employeeId == null) return;

		state = state.copyWith(isLoading: true, error: null);
		try {
			await _repository.checkIn(
				employeeId: employeeId,
			);
			state = state.copyWith(isCheckedIn: true, isLoading: false);
			await _startTracking();
		} catch (error) {
			state = state.copyWith(
				isLoading: false,
				error: error.toString(),
			);
		}
	}

	Future<void> checkOut() async {
		final employeeId = _currentEmployeeId;
		if (employeeId == null) return;

		state = state.copyWith(isLoading: true, error: null);
		try {
			await _deviceTracking.stop();
			await _repository.checkOut(employeeId: employeeId);
			state = state.copyWith(
				isCheckedIn: false,
				isLoading: false,
				isOnline: false,
			);
		} catch (error) {
			state = state.copyWith(
				isLoading: false,
				error: error.toString(),
			);
		}
	}

	Future<void> _startTracking() async {
		final employeeId = _currentEmployeeId;
		if (employeeId == null) return;

		try {
			await _deviceTracking.start(
				onLocationPoint: (Position position) async {
					await _repository.updateLocation(
						employeeId: employeeId,
						latitude: position.latitude,
						longitude: position.longitude,
						speedMetersPerSecond: position.speed,
						accuracyMeters: position.accuracy,
						isOnline: state.isOnline,
					);
				},
				onConnectivityState: (bool isOnline) async {
					state = state.copyWith(isOnline: isOnline);
					await _repository.updatePresence(
						employeeId: employeeId,
						isOnline: isOnline,
					);
				},
			);
		} catch (error) {
			state = state.copyWith(error: error.toString());
		}
	}
}

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
	if (AppConfig.useMockBackend) {
		return MockTrackingRepository();
	}

	return FirebaseTrackingRepository(FirebaseFirestore.instance);
});

final trackingControllerProvider =
		StateNotifierProvider<TrackingController, EmployeeTrackingState>((ref) {
	return TrackingController(ref);
});

final employeeStatusesProvider = StreamProvider<List<EmployeeStatus>>((ref) {
	final repository = ref.watch(trackingRepositoryProvider);
	return repository.watchEmployees();
});

final employeeStatusProvider =
		StreamProvider.family<EmployeeStatus?, String>((ref, employeeId) {
	final repository = ref.watch(trackingRepositoryProvider);
	return repository.watchEmployee(employeeId);
});

final employeeRouteProvider =
		StreamProvider.family<List<RoutePoint>, String>((ref, employeeId) {
	final repository = ref.watch(trackingRepositoryProvider);
	return repository.watchTodayRoute(employeeId);
});

final employeeVisitEvidenceProvider =
		StreamProvider.family<List<VisitEvidence>, String>((ref, employeeId) {
	final repository = ref.watch(trackingRepositoryProvider);
	return repository.watchVisitEvidence(employeeId);
});

final employeeChatMessagesProvider =
		StreamProvider.family<List<ChatMessage>, String>((ref, employeeId) {
	final repository = ref.watch(trackingRepositoryProvider);
	return repository.watchChatMessages(employeeId);
});
