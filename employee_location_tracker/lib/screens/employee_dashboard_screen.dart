import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/route_point.dart';
import '../providers/session_provider.dart';
import '../providers/tracking_provider.dart';
import 'tracker_map_widget.dart';
import '../widgets/location_name_text.dart';

class EmployeeDashboardScreen extends ConsumerWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final controllerState = ref.watch(trackingControllerProvider);
    final employeeId = session.employeeId;

    if (employeeId == null) {
      return const SizedBox.shrink();
    }

    final routeAsync = ref.watch(employeeRouteProvider(employeeId));
    final employeeStatusAsync = ref.watch(employeeStatusProvider(employeeId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Employee - ${session.employeeName ?? session.employeePhone ?? 'Profile'}'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _StatusPill(
                          label: controllerState.isCheckedIn ? 'Checked In' : 'Checked Out',
                          color: controllerState.isCheckedIn ? Colors.green : Colors.orange,
                        ),
                        _StatusPill(
                          label: controllerState.isOnline ? 'Online' : 'Offline',
                          color: controllerState.isOnline ? Colors.blue : Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    employeeStatusAsync.when(
                      loading: () => const Text('Distance today: --'),
                      error: (_, stackTrace) => const Text('Distance today: --'),
                      data: (status) {
                        final distance =
                            (((status?.totalDistanceMeters ?? 0) / 1000))
                                .toStringAsFixed(2);
                        if (status?.latitude != null && status?.longitude != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Distance today: $distance km'),
                              LocationNameText(
                                latitude: status!.latitude!,
                                longitude: status.longitude!,
                                prefix: 'Current location: ',
                              ),
                            ],
                          );
                        }
                        return Text('Distance today: $distance km');
                      },
                    ),
                    if (controllerState.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          controllerState.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: controllerState.isLoading
                          ? null
                          : () {
                              final notifier = ref.read(trackingControllerProvider.notifier);
                              if (controllerState.isCheckedIn) {
                                notifier.checkOut();
                              } else {
                                notifier.checkIn();
                              }
                            },
                      child: Text(controllerState.isCheckedIn ? 'Check Out' : 'Check In'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: routeAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
                data: (points) => _EmployeeRouteMap(points: points),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeRouteMap extends StatelessWidget {
  const _EmployeeRouteMap({required this.points});

  final List<RoutePoint> points;

  @override
  Widget build(BuildContext context) {
    final initial = points.isNotEmpty
        ? ll.LatLng(points.last.latitude, points.last.longitude)
        : ll.LatLng(28.6139, 77.2090);

    double? currentLatitude;
    double? currentLongitude;
    if (points.isNotEmpty) {
      final latest = points.last;
      currentLatitude = latest.latitude;
      currentLongitude = latest.longitude;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: TrackerMapWidget(
        initialLatitude: initial.latitude,
        initialLongitude: initial.longitude,
        route: points
            .map((point) => ll.LatLng(point.latitude, point.longitude))
            .toList(growable: false),
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
        autoFollowCurrentLocation: true,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
