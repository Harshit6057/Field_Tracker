import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../models/employee_status.dart';
import '../models/route_point.dart';
import '../models/tracking_alert.dart';
import '../models/tracking_analytics.dart';
import '../models/work_zone.dart';
import '../providers/tracking_provider.dart';
import '../providers/location_filter_provider.dart';
import '../services/heat_map_utils.dart';
import '../widgets/location_tracking_map_widget.dart';

class LocationTrackingDashboardScreen extends ConsumerStatefulWidget {
  const LocationTrackingDashboardScreen({super.key});

  @override
  ConsumerState<LocationTrackingDashboardScreen> createState() =>
      _LocationTrackingDashboardScreenState();
}

class _LocationTrackingDashboardScreenState
    extends ConsumerState<LocationTrackingDashboardScreen> {
  String? _selectedEmployeeId;
  int _tabIndex = 0;
  DateTime _reportDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeeStatusesProvider);
    final filter = ref.watch(locationFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-time Location Tracking'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(employeeStatusesProvider),
          ),
        ],
      ),
      body: employeesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, st) => Center(child: Text('Error: $error')),
        data: (allEmployees) {
          if (allEmployees.isEmpty) {
            return const Center(child: Text('No employees found'));
          }

          // Apply filters
          final filteredEmployees = _applyFilters(allEmployees, filter);

          if (_selectedEmployeeId == null ||
              !filteredEmployees.any(
                (e) => e.employeeId == _selectedEmployeeId,
              )) {
            _selectedEmployeeId = filteredEmployees.isNotEmpty
                ? filteredEmployees.first.employeeId
                : allEmployees.first.employeeId;
          }

          return _buildDashboard(
            context,
            ref,
            allEmployees,
            filteredEmployees,
            _selectedEmployeeId!,
          );
        },
      ),
    );
  }

  Widget _buildGeofencingTab(List<EmployeeStatus> employees) {
    final zonesAsync = ref.watch(workZonesProvider);
    final alertsAsync = ref.watch(trackingAlertsProvider);
    final employeeNames = {
      for (final employee in employees) employee.employeeId: employee.employeeName,
    };

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Work Zones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showWorkZoneDialog(employees),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add Zone'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Card(
                    child: zonesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, st) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Error: $error'),
                      ),
                      data: (zones) {
                        if (zones.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No work zones defined yet.'),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: zones.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final zone = zones[index];
                            final assignedNames = zone.assignedEmployeeIds
                                .map((id) => employeeNames[id] ?? id)
                                .toList(growable: false);
                            final assignedText = zone.assignedEmployeeIds.isEmpty
                                ? 'All employees'
                                : assignedNames.join(', ');
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.fence),
                              title: Text(zone.name),
                              subtitle: Text(
                                'Radius: ${zone.radiusMeters.toStringAsFixed(0)} m\nAssigned: $assignedText',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit zone',
                                    onPressed: () => _showWorkZoneDialog(
                                      employees,
                                      existingZone: zone,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete zone',
                                    onPressed: () => _deleteZone(zone.id),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                const SliverToBoxAdapter(
                  child: Text(
                    'Recent Geofence Alerts',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Card(
                    child: alertsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (error, st) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Error: $error'),
                      ),
                      data: (alerts) {
                        if (alerts.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No geofence alerts yet.'),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: alerts.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final alert = alerts[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(_alertIcon(alert.type)),
                              title: Text(alert.title),
                              subtitle: Text(
                                '${alert.employeeName} • ${DateFormat('dd MMM hh:mm a').format(alert.timestamp)}\n${alert.message}',
                              ),
                              isThreeLine: true,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _alertIcon(TrackingAlertType type) {
    switch (type) {
      case TrackingAlertType.arrival:
        return Icons.login;
      case TrackingAlertType.departure:
        return Icons.logout;
      case TrackingAlertType.outOfZone:
        return Icons.warning_amber_rounded;
    }
  }

  Future<void> _showWorkZoneDialog(
    List<EmployeeStatus> employees, {
    WorkZone? existingZone,
  }) async {
    final nameController = TextEditingController(text: existingZone?.name ?? '');
    final latitudeController = TextEditingController(
      text: existingZone?.centerLatitude.toString() ?? '',
    );
    final longitudeController = TextEditingController(
      text: existingZone?.centerLongitude.toString() ?? '',
    );
    final radiusController = TextEditingController(
      text: existingZone?.radiusMeters.toStringAsFixed(0) ?? '150',
    );
    final selectedEmployees = existingZone == null
        ? <String>{}
        : existingZone.assignedEmployeeIds.toSet();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existingZone == null ? 'Create Work Zone' : 'Edit Work Zone'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Zone Name',
                        ),
                      ),
                      TextField(
                        controller: latitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Center Latitude',
                        ),
                      ),
                      TextField(
                        controller: longitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Center Longitude',
                        ),
                      ),
                      TextField(
                        controller: radiusController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Radius (meters)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Assign to employees (optional)'),
                      ),
                      ...employees.map(
                        (employee) => CheckboxListTile(
                          dense: true,
                          title: Text(employee.employeeName),
                          value: selectedEmployees.contains(
                            employee.employeeId,
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value ?? false) {
                                selectedEmployees.add(employee.employeeId);
                              } else {
                                selectedEmployees.remove(employee.employeeId);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final latitude = double.tryParse(
                      latitudeController.text.trim(),
                    );
                    final longitude = double.tryParse(
                      longitudeController.text.trim(),
                    );
                    final radius = double.tryParse(
                      radiusController.text.trim(),
                    );

                    if (name.isEmpty ||
                        latitude == null ||
                        longitude == null ||
                        radius == null ||
                        radius <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter valid zone details.'),
                        ),
                      );
                      return;
                    }

                    await ref
                        .read(trackingRepositoryProvider)
                        .saveWorkZone(
                          WorkZone(
                            id: existingZone?.id ?? '',
                            name: name,
                            centerLatitude: latitude,
                            centerLongitude: longitude,
                            radiusMeters: radius,
                            assignedEmployeeIds: selectedEmployees.toList(
                              growable: false,
                            ),
                            isActive: existingZone?.isActive ?? true,
                            createdAt: existingZone?.createdAt,
                          ),
                        );
                    if (!mounted) return;
                    Navigator.of(this.context).pop();
                  },
                  child: Text(existingZone == null ? 'Save Zone' : 'Update Zone'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteZone(String zoneId) async {
    await ref.read(trackingRepositoryProvider).deleteWorkZone(zoneId);
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _reportDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _reportDate = picked;
      });
    }
  }

  Future<void> _exportCsv(DailyTrackingReport report) async {
    final service = ref.read(trackingExportServiceProvider);
    final exported = await service.exportDailyReportCsv(report);
    if (!mounted) return;
    _showExportSnackBar(
      message: 'CSV exported to ${exported.path}',
      filePath: exported.path,
    );
  }

  Future<void> _exportPdf(DailyTrackingReport report) async {
    final service = ref.read(trackingExportServiceProvider);
    final exported = await service.exportDailyReportPdf(report);
    if (!mounted) return;
    _showExportSnackBar(
      message: 'PDF exported to ${exported.path}',
      filePath: exported.path,
    );
  }

  void _showExportSnackBar({required String message, required String filePath}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            _openExportedFile(filePath);
          },
        ),
      ),
    );
  }

  Future<void> _openExportedFile(String filePath) async {
    final result = await OpenFilex.open(filePath);
    if (!mounted || result.type == ResultType.done) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message.isEmpty
              ? 'Could not open exported file.'
              : 'Could not open exported file: ${result.message}',
        ),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    List<EmployeeStatus> allEmployees,
    List<EmployeeStatus> filteredEmployees,
    String selectedId,
  ) {
    final routeAsync = ref.watch(employeeRouteProvider(selectedId));
    final allRoutesAsync = _getAllRoutes(ref, allEmployees);

    return DefaultTabController(
      length: 4,
      initialIndex: _tabIndex,
      child: Column(
        children: [
          TabBar(
            onTap: (index) => setState(() => _tabIndex = index),
            tabs: const [
              Tab(icon: Icon(Icons.map), text: 'Map View'),
              Tab(icon: Icon(Icons.list), text: 'Employee List'),
              Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
              Tab(icon: Icon(Icons.fence), text: 'Geofencing'),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Map View Tab
                _buildMapTab(
                  ref,
                  filteredEmployees,
                  selectedId,
                  routeAsync,
                  allRoutesAsync,
                ),

                // Employee List Tab
                _buildEmployeeListTab(
                  filteredEmployees,
                  selectedId,
                  allEmployees,
                ),

                // Analytics Tab
                _buildAnalyticsTab(selectedId, filteredEmployees),

                // Geofencing Tab
                _buildGeofencingTab(allEmployees),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTab(
    WidgetRef ref,
    List<EmployeeStatus> filteredEmployees,
    String selectedId,
    AsyncValue<List<RoutePoint>> routeAsync,
    AsyncValue<List<RoutePoint>> allRoutesAsync,
  ) {
    final filter = ref.watch(locationFilterProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: _buildMapControls(ref),
        ),
        Expanded(
          child: routeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, st) => Center(child: Text('Error: $error')),
            data: (points) => allRoutesAsync.when(
              loading: () => LocationTrackingMapWidget(
                employees: filteredEmployees,
                selectedEmployeeId: selectedId,
                points: points,
                onEmployeeSelected: (id) =>
                    setState(() => _selectedEmployeeId = id),
              ),
              error: (_, _) => LocationTrackingMapWidget(
                employees: filteredEmployees,
                selectedEmployeeId: selectedId,
                points: points,
                onEmployeeSelected: (id) =>
                    setState(() => _selectedEmployeeId = id),
                showHeatMap: filter.showOnlineOnly, // Use as toggle for demo
              ),
              data: (allPoints) => LocationTrackingMapWidget(
                employees: filteredEmployees,
                selectedEmployeeId: selectedId,
                points: points,
                allRoutePoints: allPoints,
                showHeatMap: filter.showOnlineOnly,
                onEmployeeSelected: (id) =>
                    setState(() => _selectedEmployeeId = id),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapControls(WidgetRef ref) {
    final filter = ref.watch(locationFilterProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search employee...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    onChanged: (value) => ref
                        .read(locationFilterProvider.notifier)
                        .setSearchQuery(value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Advanced Filters',
                  onPressed: () => _showFilterDialog(ref),
                ),
              ],
            ),
            if (filter.showOnlineOnly || filter.showCheckedInOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (filter.showOnlineOnly)
                      _buildFilterChip(
                        ref,
                        'Online Only',
                        onDelete: () => ref
                            .read(locationFilterProvider.notifier)
                            .setOnlineFilter(false),
                      ),
                    if (filter.showCheckedInOnly)
                      _buildFilterChip(
                        ref,
                        'Checked-In Only',
                        onDelete: () => ref
                            .read(locationFilterProvider.notifier)
                            .setCheckedInFilter(false),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    WidgetRef ref,
    String label, {
    required VoidCallback onDelete,
  }) {
    return Chip(
      label: Text(label),
      onDeleted: onDelete,
      deleteIcon: const Icon(Icons.close, size: 18),
    );
  }

  void _showFilterDialog(WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(child: _buildFilterDialogContent(ref)),
        ),
      ),
    );
  }

  Widget _buildFilterDialogContent(WidgetRef ref) {
    final filter = ref.watch(locationFilterProvider);
    final notifier = ref.read(locationFilterProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filters',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          title: const Text('Online Only'),
          value: filter.showOnlineOnly,
          onChanged: (value) => notifier.setOnlineFilter(value ?? false),
        ),
        CheckboxListTile(
          title: const Text('Checked-In Only'),
          value: filter.showCheckedInOnly,
          onChanged: (value) => notifier.setCheckedInFilter(value ?? false),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => notifier.reset(),
              child: const Text('Reset All'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }



  List<EmployeeStatus> _applyFilters(
    List<EmployeeStatus> employees,
    LocationFilter filter,
  ) {
    var filtered = employees;

    if (filter.showOnlineOnly) {
      filtered = filtered.where((e) => e.isOnline).toList();
    }

    if (filter.showCheckedInOnly) {
      filtered = filtered.where((e) => e.isCheckedIn).toList();
    }

    if (filter.searchQuery.isNotEmpty) {
      final query = filter.searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (e) =>
                e.employeeName.toLowerCase().contains(query) ||
                (e.phoneNumber?.contains(query) ?? false),
          )
          .toList();
    }

    return filtered;
  }

  Widget _buildEmployeeListTab(
    List<EmployeeStatus> filteredEmployees,
    String selectedId,
    List<EmployeeStatus> allEmployees,
  ) {
    final zonesAsync = ref.watch(workZonesProvider);

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filteredEmployees.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final employee = filteredEmployees[index];
        final isSelected = employee.employeeId == selectedId;
        final durationInShift = employee.checkInTime != null
            ? DateTime.now().difference(employee.checkInTime!)
            : Duration.zero;
        final assignedZoneNames = zonesAsync.maybeWhen(
          data: (zones) => zones
              .where(
                (zone) =>
                    zone.assignedEmployeeIds.isEmpty ||
                    zone.assignedEmployeeIds.contains(employee.employeeId),
              )
              .map((zone) => zone.name)
              .toList(growable: false),
          orElse: () => const <String>[],
        );

        return Card(
          elevation: isSelected ? 4 : 0,
          color: isSelected ? Colors.blue.shade50 : null,
          child: ListTile(
            selected: isSelected,
            onTap: () =>
                setState(() => _selectedEmployeeId = employee.employeeId),
            leading: CircleAvatar(
              backgroundColor: employee.isOnline ? Colors.green : Colors.grey,
              child: Text(employee.employeeName[0].toUpperCase()),
            ),
            title: Text(employee.employeeName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${employee.isCheckedIn ? 'Checked In' : 'Out'} • ${employee.isOnline ? 'Online' : 'Offline'} • Last: ${DateFormat('hh:mm a').format(employee.lastSeen)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  assignedZoneNames.isEmpty
                      ? 'Work Zones: None assigned'
                      : 'Work Zones: ${assignedZoneNames.join(', ')}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            trailing: employee.checkInTime != null
                ? Tooltip(
                    message: 'Duration in shift',
                    child: Text(
                      _formatDuration(durationInShift),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildAnalyticsTab(
    String selectedId,
    List<EmployeeStatus> filteredEmployees,
  ) {
    final selectedEmployee = filteredEmployees
        .where((employee) => employee.employeeId == selectedId)
        .firstOrNull;

    if (selectedEmployee == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No employees match current filters. Clear filters to view analytics.',
          ),
        ),
      );
    }

    final reportAsync = ref.watch(
      dailyTrackingReportProvider(
        DailyReportRequest(
          employeeId: selectedEmployee.employeeId,
          date: DateTime(_reportDate.year, _reportDate.month, _reportDate.day),
        ),
      ),
    );

    return reportAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, st) => Center(child: Text('Error: $error')),
      data: (report) {
        final metrics = HeatMapUtils.getActivityMetrics(report.points);
        final durationInShift = selectedEmployee.checkInTime != null
            ? DateTime.now().difference(selectedEmployee.checkInTime!)
            : Duration.zero;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Report Date: ${DateFormat('dd MMM yyyy').format(_reportDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickReportDate,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Change Date'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _exportCsv(report),
                    icon: const Icon(Icons.table_view),
                    label: const Text('Export CSV'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _exportPdf(report),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMetricCard('Employee: ${selectedEmployee.employeeName}', [
                'Location: ${selectedEmployee.latitude?.toStringAsFixed(4) ?? '--'}, ${selectedEmployee.longitude?.toStringAsFixed(4) ?? '--'}',
                'Status: ${selectedEmployee.isCheckedIn ? 'Checked In' : 'Checked Out'} • ${selectedEmployee.isOnline ? 'Online' : 'Offline'}',
                'In Shift: ${_formatDuration(durationInShift)}',
              ]),
              const SizedBox(height: 16),
              _buildMetricCard('Route Analytics', [
                'Total Points: ${metrics['totalPoints']}',
                'Active Duration: ${_formatDuration(report.activeDuration)}',
                'Total Distance: ${(report.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
              ]),
              const SizedBox(height: 16),
              _buildMetricCard('Speed Metrics', [
                'Avg Speed: ${(metrics['avgSpeedMps'] * 3.6).toStringAsFixed(2)} km/h',
                'Max Speed: ${(metrics['maxSpeedMps'] * 3.6).toStringAsFixed(2)} km/h',
              ]),
              const SizedBox(height: 16),
              _buildMetricCard(
                'Dwell Time',
                report.dwellPeriods.isEmpty
                    ? const ['No significant dwell periods found.']
                    : report.dwellPeriods
                          .map(
                            (dwell) =>
                                '${DateFormat('hh:mm a').format(dwell.startTime)} - ${DateFormat('hh:mm a').format(dwell.endTime)} • ${dwell.duration.inMinutes} min • ${dwell.zoneName ?? 'Unknown location'}',
                          )
                          .toList(growable: false),
              ),
              const SizedBox(height: 16),
              _buildMetricCard('Summary', [
                'Distance (live): ${(selectedEmployee.totalDistanceMeters / 1000).toStringAsFixed(2)} km',
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, List<String> metrics) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...metrics.map(
              (metric) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Text(metric),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  AsyncValue<List<RoutePoint>> _getAllRoutes(
    WidgetRef ref,
    List<EmployeeStatus> employees,
  ) {
    // Get all routes from all employees for heat map
    return ref.watch(
      employeeRouteProvider(
        employees.isNotEmpty ? employees.first.employeeId : '',
      ),
    );
  }
}
