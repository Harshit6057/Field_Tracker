import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/route_point.dart';
import '../models/chat_message.dart';
import '../models/visit_evidence.dart';
import '../providers/session_provider.dart';
import '../providers/tracking_provider.dart';
import 'chat_screen.dart';
import 'tracker_map_widget.dart';
import '../widgets/location_name_text.dart';

class EmployeeDashboardScreen extends ConsumerStatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  ConsumerState<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends ConsumerState<EmployeeDashboardScreen> {
  Future<void> _openEvidenceComposer(String employeeId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CaptureVisitEvidenceSheet(employeeId: employeeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final controllerState = ref.watch(trackingControllerProvider);
    final employeeId = session.employeeId;

    if (employeeId == null) {
      return const SizedBox.shrink();
    }

    final routeAsync = ref.watch(employeeRouteProvider(employeeId));
    final employeeStatusAsync = ref.watch(employeeStatusProvider(employeeId));
  final visitEvidenceAsync = ref.watch(employeeVisitEvidenceProvider(employeeId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Employee - ${session.employeeName ?? session.employeePhone ?? 'Profile'}'),
        actions: [
          IconButton(
            tooltip: 'Chat with admin',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatScreen(
                    employeeId: employeeId,
                    title: 'Chat with Admin',
                    senderRole: ChatSenderRole.employee,
                    senderName: session.employeeName ?? 'Employee',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: controllerState.isCheckedIn
                          ? () => _openEvidenceComposer(employeeId)
                          : null,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Capture Visit Photo + Remarks'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: routeAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(child: Text(error.toString())),
                      data: (points) => _EmployeeRouteMap(points: points),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.photo_camera_back_outlined, size: 18),
                              const SizedBox(width: 6),
                              const Text(
                                'Visit Evidence',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              if (visitEvidenceAsync.asData?.value.isNotEmpty ??
                                  false)
                                Text(
                                  '${visitEvidenceAsync.asData?.value.length ?? 0} photos',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _VisitEvidencePanel(evidenceAsync: visitEvidenceAsync),
                        ),
                      ],
                    ),
                  ),
                ],
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

class _CaptureVisitEvidenceSheet extends ConsumerStatefulWidget {
  const _CaptureVisitEvidenceSheet({required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<_CaptureVisitEvidenceSheet> createState() =>
      _CaptureVisitEvidenceSheetState();
}

class _CaptureVisitEvidenceSheetState
    extends ConsumerState<_CaptureVisitEvidenceSheet> {
  final TextEditingController _remarksController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  VisitEvidenceType _type = VisitEvidenceType.place;
  Uint8List? _photoBytes;
  double? _latitude;
  double? _longitude;
  String? _locationName;
  bool _isCapturing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Visit Evidence', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Capture the photo first. Location and place name are automatically attached.',
              ),
              const SizedBox(height: 14),
              SegmentedButton<VisitEvidenceType>(
                segments: const [
                  ButtonSegment<VisitEvidenceType>(
                    value: VisitEvidenceType.place,
                    label: Text('Place'),
                    icon: Icon(Icons.place_outlined),
                  ),
                  ButtonSegment<VisitEvidenceType>(
                    value: VisitEvidenceType.person,
                    label: Text('Person'),
                    icon: Icon(Icons.person_outline),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() => _type = selection.first);
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isCapturing || _isSaving ? null : _captureWithLocation,
                icon: Icon(_photoBytes == null ? Icons.camera_alt : Icons.camera_alt_outlined),
                label: Text(_photoBytes == null ? 'Capture Photo' : 'Retake Photo'),
              ),
              if (_isCapturing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_photoBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _photoBytes!,
                    height: 210,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _remarksController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Remarks',
                  hintText:
                      'Example: I spoke to the owner, discussed product demand and confirmed next follow-up date.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 10),
                _LocationReadout(
                  latitude: _latitude!,
                  longitude: _longitude!,
                  locationName: _locationName,
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving...' : 'Save Visit Evidence'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureWithLocation() async {
    setState(() {
      _isCapturing = true;
    });

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) {
        return;
      }

      final bytes = await file.readAsBytes();
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final resolvedLocation = await _resolveLocationName(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationName = resolvedLocation;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final bytes = _photoBytes;
    final latitude = _latitude;
    final longitude = _longitude;
    final remarks = _remarksController.text.trim();

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a photo first.')),
      );
      return;
    }
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to capture location for this photo.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await ref.read(trackingRepositoryProvider).addVisitEvidence(
            employeeId: widget.employeeId,
            type: _type,
            remarks: remarks,
            latitude: latitude,
            longitude: longitude,
            locationName: _locationName ??
                '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
            photoBytes: bytes,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Visit evidence saved successfully!'),
          duration: Duration(milliseconds: 1500),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save evidence: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<String> _resolveLocationName(double latitude, double longitude) async {
    try {
      final places = await placemarkFromCoordinates(latitude, longitude);
      if (places.isNotEmpty) {
        final place = places.first;
        final chunks = <String>[
          if ((place.name ?? '').trim().isNotEmpty) place.name!.trim(),
          if ((place.subLocality ?? '').trim().isNotEmpty)
            place.subLocality!.trim(),
          if ((place.locality ?? '').trim().isNotEmpty) place.locality!.trim(),
          if ((place.administrativeArea ?? '').trim().isNotEmpty)
            place.administrativeArea!.trim(),
        ];
        if (chunks.isNotEmpty) {
          return chunks.join(', ');
        }
      }
    } catch (_) {
      // Fallback below.
    }

    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }
}

class _LocationReadout extends StatelessWidget {
  const _LocationReadout({
    required this.latitude,
    required this.longitude,
    required this.locationName,
  });

  final double latitude;
  final double longitude;
  final String? locationName;

  @override
  Widget build(BuildContext context) {
    final marker = TrackerMapMarker(
      point: ll.LatLng(latitude, longitude),
      color: Colors.red,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            title: Text(locationName ?? 'Resolving location...'),
            subtitle: Text(
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
            ),
          ),
          SizedBox(
            height: 120,
            child: TrackerMapWidget(
              initialLatitude: latitude,
              initialLongitude: longitude,
              route: const [],
              otherMarkers: [marker],
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitEvidencePanel extends StatelessWidget {
  const _VisitEvidencePanel({required this.evidenceAsync});

  final AsyncValue<List<VisitEvidence>> evidenceAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: evidenceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.orange, size: 32),
                const SizedBox(height: 8),
                Text('Could not load visit evidence'),
                Text(
                  '$error',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No visit photos yet. Capture a photo and add remarks after each field visit.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return _VisitEvidenceCard(item: item);
            },
          );
        },
      ),
    );
  }
}

class _VisitEvidenceCard extends StatelessWidget {
  const _VisitEvidenceCard({required this.item});

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
              '${item.typeLabel} Visit • ${DateFormat('dd MMM, HH:mm').format(item.timestamp)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _EvidenceImage(item: item),
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
            Text(
              item.remarks.isEmpty ? 'No remarks added' : item.remarks,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceImage extends StatelessWidget {
  const _EvidenceImage({required this.item});

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
            errorBuilder: (context, error, stackTrace) {
              return _imageFallback();
            },
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

    return _imageFallback();
  }

  Widget _imageFallback() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 42),
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
