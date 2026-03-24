import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/visit_evidence.dart';
import '../providers/session_provider.dart';
import '../providers/tracking_provider.dart';
import 'tracker_map_widget.dart';
import '../widgets/location_name_text.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String? _selectedEmployeeId;

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeeStatusesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Control Room'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: employeesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (employees) {
          if (employees.isEmpty) {
            return const Center(child: Text('No employees found.'));
          }

          _selectedEmployeeId ??= employees.first.employeeId;
          final selectedId = _selectedEmployeeId ?? employees.first.employeeId;
          final routeAsync = ref.watch(employeeRouteProvider(selectedId));
          final evidenceAsync = ref.watch(employeeVisitEvidenceProvider(selectedId));

          return LayoutBuilder(
            builder: (context, constraints) {
              final useColumnLayout = constraints.maxWidth < 960;

              final listSection = _EmployeeList(
                employees: employees,
                selectedEmployeeId: selectedId,
                onSelect: (value) => setState(() => _selectedEmployeeId = value),
              );

              final mapSection = routeAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text(error.toString())),
                data: (points) => _AdminMap(
                  employees: employees,
                  selectedEmployeeId: selectedId,
                  points: points,
                  evidenceAsync: evidenceAsync,
                ),
              );

              if (useColumnLayout) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(height: 220, child: listSection),
                      const SizedBox(height: 12),
                      Expanded(child: mapSection),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(width: 300, child: listSection),
                    const SizedBox(width: 12),
                    Expanded(child: mapSection),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmployeeList extends StatelessWidget {
  const _EmployeeList({
    required this.employees,
    required this.selectedEmployeeId,
    required this.onSelect,
  });

  final List<EmployeeStatus> employees;
  final String selectedEmployeeId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: employees.length,
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final employee = employees[index];
          final selected = employee.employeeId == selectedEmployeeId;

          return ListTile(
            selected: selected,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
            onTap: () => onSelect(employee.employeeId),
            title: Text(employee.employeeName),
            subtitle: Text(
              '${employee.phoneNumber ?? 'No phone'} • Last seen ${DateFormat.Hm().format(employee.lastSeen)}',
            ),
            trailing: SizedBox(
              width: 170,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _Badge(
                    label: employee.isCheckedIn ? 'IN' : 'OUT',
                    color: employee.isCheckedIn ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  _Badge(
                    label: employee.isOnline ? 'ONLINE' : 'OFFLINE',
                    color: employee.isOnline ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Call employee',
                    onPressed: employee.phoneNumber == null
                        ? null
                        : () => _callEmployee(employee.phoneNumber!),
                    icon: const Icon(Icons.call),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _callEmployee(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    await launchUrl(uri);
  }
}

class _AdminMap extends StatelessWidget {
  const _AdminMap({
    required this.employees,
    required this.selectedEmployeeId,
    required this.points,
    required this.evidenceAsync,
  });

  final List<EmployeeStatus> employees;
  final String selectedEmployeeId;
  final List<RoutePoint> points;
  final AsyncValue<List<VisitEvidence>> evidenceAsync;

  @override
  Widget build(BuildContext context) {
    final selectedEmployee = employees.firstWhere(
      (employee) => employee.employeeId == selectedEmployeeId,
      orElse: () => employees.first,
    );

    final focus = points.isNotEmpty
        ? ll.LatLng(points.last.latitude, points.last.longitude)
        : ll.LatLng(selectedEmployee.latitude ?? 28.6139, selectedEmployee.longitude ?? 77.2090);

    final markers = employees
        .where((employee) => employee.latitude != null && employee.longitude != null)
        .map(
          (employee) => TrackerMapMarker(
            point: ll.LatLng(employee.latitude!, employee.longitude!),
            color: employee.employeeId == selectedEmployeeId
                ? Colors.blue
                : Colors.red,
          ),
        )
        .toList(growable: false);

    final latestPoint = points.isNotEmpty ? points.last : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text('Route for ${selectedEmployee.employeeName}'),
              subtitle: Text(
                'Distance: ${(selectedEmployee.totalDistanceMeters / 1000).toStringAsFixed(2)} km • '
                'Points: ${points.length}',
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _Badge(
                    label: selectedEmployee.isOnline ? 'ONLINE' : 'OFFLINE',
                    color: selectedEmployee.isOnline ? Colors.blue : Colors.grey,
                  ),
                  _Badge(
                    label: selectedEmployee.isCheckedIn ? 'CHECKED-IN' : 'CHECKED-OUT',
                    color: selectedEmployee.isCheckedIn ? Colors.green : Colors.orange,
                  ),
                  _Badge(
                    label: 'PHONE: ${selectedEmployee.phoneNumber ?? '--'}',
                    color: Colors.brown,
                  ),
                  _Badge(
                    label: 'LAST: ${DateFormat('dd MMM, HH:mm').format(selectedEmployee.lastSeen)}',
                    color: Colors.black54,
                  ),
                  _Badge(
                    label: 'CHECK-IN: ${selectedEmployee.checkInTime != null ? DateFormat('HH:mm').format(selectedEmployee.checkInTime!) : '--'}',
                    color: Colors.indigo,
                  ),
                  _Badge(
                    label: 'CHECK-OUT: ${selectedEmployee.checkOutTime != null ? DateFormat('HH:mm').format(selectedEmployee.checkOutTime!) : '--'}',
                    color: Colors.teal,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 320,
              child: TrackerMapWidget(
                initialLatitude: focus.latitude,
                initialLongitude: focus.longitude,
                route: points
                    .map((point) => ll.LatLng(point.latitude, point.longitude))
                    .toList(growable: false),
                currentLatitude: latestPoint?.latitude,
                currentLongitude: latestPoint?.longitude,
                otherMarkers: markers,
                autoFollowCurrentLocation: true,
              ),
            ),
            if (points.isNotEmpty) const Divider(height: 1),
            if (points.isNotEmpty)
              SizedBox(
                height: 130,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemBuilder: (context, index) {
                    final reverseIndex = points.length - 1 - index;
                    final point = points[reverseIndex];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('HH:mm:ss').format(point.timestamp)}  ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Expanded(
                          child: LocationNameText(
                            latitude: point.latitude,
                            longitude: point.longitude,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    );
                  },
                  separatorBuilder: (_, index) => const SizedBox(height: 6),
                  itemCount: points.length > 12 ? 12 : points.length,
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.photo_camera_back_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Visit Evidence',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${evidenceAsync.asData?.value.length ?? 0} photo${(evidenceAsync.asData?.value.length ?? 0) != 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            evidenceAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orange, size: 32),
                    const SizedBox(height: 8),
                    const Text('Failed to load visit evidence'),
                    Text(
                      '$error',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: Text('No visit photos/remarks submitted yet.')),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    return _AdminEvidenceCard(item: items[index]);
                  },
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemCount: items.length,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEvidenceCard extends StatelessWidget {
  const _AdminEvidenceCard({required this.item});

  final VisitEvidence item;

  @override
  Widget build(BuildContext context) {
    final marker = TrackerMapMarker(
      point: ll.LatLng(item.latitude, item.longitude),
      color: Colors.red,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.typeLabel} • ${DateFormat('dd MMM, HH:mm').format(item.timestamp)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _AdminEvidenceImage(item: item),
            const SizedBox(height: 8),
            Text(
              item.locationName,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${item.latitude.toStringAsFixed(5)}, ${item.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: TrackerMapWidget(
                initialLatitude: item.latitude,
                initialLongitude: item.longitude,
                route: const [],
                otherMarkers: [marker],
              ),
            ),
            const SizedBox(height: 8),
            Text(item.remarks.isEmpty ? 'No remarks added' : item.remarks),
          ],
        ),
      ),
    );
  }
}

class _AdminEvidenceImage extends StatelessWidget {
  const _AdminEvidenceImage({required this.item});

  final VisitEvidence item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.photoUrl;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _openPreview(context),
          child: Image.network(
            imageUrl,
            height: 220,
            width: double.infinity,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => _fallback(),
          ),
        ),
      );
    }

    if (item.localPhotoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _openPreview(context),
          child: Image.memory(
            item.localPhotoBytes!,
            height: 220,
            width: double.infinity,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 38),
    );
  }

  void _openPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final imageUrl = item.photoUrl;
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    )
                  : Image.memory(
                      item.localPhotoBytes!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
