import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../screens/tracker_map_widget.dart';
import '../services/heat_map_utils.dart';

class LocationTrackingMapWidget extends StatefulWidget {
  const LocationTrackingMapWidget({
    super.key,
    required this.employees,
    required this.selectedEmployeeId,
    required this.points,
    required this.onEmployeeSelected,
    this.showHeatMap = false,
    this.allRoutePoints = const [],
  });

  final List<EmployeeStatus> employees;
  final String? selectedEmployeeId;
  final List<RoutePoint> points;
  final ValueChanged<String> onEmployeeSelected;
  final bool showHeatMap;
  final List<RoutePoint> allRoutePoints;

  @override
  State<LocationTrackingMapWidget> createState() =>
      _LocationTrackingMapWidgetState();
}

class _LocationTrackingMapWidgetState extends State<LocationTrackingMapWidget> {
  List<TrackerMapMarker> _buildMarkers() {
    final markers = <TrackerMapMarker>[];

    for (final employee in widget.employees) {
      if (employee.latitude == null || employee.longitude == null) continue;
      final isSelected = employee.employeeId == widget.selectedEmployeeId;
      final color = isSelected
          ? Colors.blue
          : employee.isOnline
          ? Colors.green
          : Colors.red;

      markers.add(
        TrackerMapMarker(
          point: ll.LatLng(employee.latitude!, employee.longitude!),
          color: color,
        ),
      );
    }

    if (widget.showHeatMap && widget.allRoutePoints.isNotEmpty) {
      final heatMapPoints = HeatMapUtils.generateHeatMapFromRoutes(
        widget.allRoutePoints,
      );
      for (final point in heatMapPoints) {
        markers.add(
          TrackerMapMarker(
            point: ll.LatLng(point.latitude, point.longitude),
            color: HeatMapUtils.getHeatMapColor(point.intensity),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final selectedEmployeeOrNull = widget.employees
        .where((employee) => employee.employeeId == widget.selectedEmployeeId)
        .firstOrNull;
    final selectedEmployee =
        selectedEmployeeOrNull ??
        (widget.employees.isNotEmpty ? widget.employees.first : null);

    final initialLat = selectedEmployee?.latitude ?? 28.6139;
    final initialLng = selectedEmployee?.longitude ?? 77.2090;
    final route = widget.points
        .map((point) => ll.LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final markers = _buildMarkers();
    final latestPoint = widget.points.isNotEmpty ? widget.points.last : null;

    return Column(
      children: [
        Expanded(
          child: TrackerMapWidget(
            initialLatitude: initialLat,
            initialLongitude: initialLng,
            route: route,
            currentLatitude: latestPoint?.latitude,
            currentLongitude: latestPoint?.longitude,
            otherMarkers: markers,
            autoFollowCurrentLocation: true,
          ),
        ),
        if (selectedEmployee != null)
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              '${selectedEmployee.employeeName} • ${selectedEmployee.isCheckedIn ? 'Checked In' : 'Checked Out'} • ${selectedEmployee.isOnline ? 'Online' : 'Offline'} • Last: ${DateFormat('hh:mm a').format(selectedEmployee.lastSeen)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
