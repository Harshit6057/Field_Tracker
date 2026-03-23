import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

class TrackerMapWidget extends StatefulWidget {
  const TrackerMapWidget({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.route,
    this.currentLatitude,
    this.currentLongitude,
    this.otherMarkers = const [],
    this.autoFollowCurrentLocation = false,
  });

  final double initialLatitude;
  final double initialLongitude;
  final List<ll.LatLng> route;
  final double? currentLatitude;
  final double? currentLongitude;
  final List<TrackerMapMarker> otherMarkers;
  final bool autoFollowCurrentLocation;

  @override
  State<TrackerMapWidget> createState() => _TrackerMapWidgetState();
}

class _TrackerMapWidgetState extends State<TrackerMapWidget> {
  late final MapController _mapController;
  ll.LatLng? _detectedCurrentLocation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(covariant TrackerMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.autoFollowCurrentLocation) {
      return;
    }

    final oldLat = oldWidget.currentLatitude;
    final oldLng = oldWidget.currentLongitude;
    final newLat = widget.currentLatitude;
    final newLng = widget.currentLongitude;

    if (oldLat == null || oldLng == null || newLat == null || newLng == null) {
      return;
    }

    final moved = (oldLat - newLat).abs() > 0.00002 ||
        (oldLng - newLng).abs() > 0.00002;
    if (moved) {
      final center = ll.LatLng(newLat, newLng);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(center, _mapController.camera.zoom);
        }
      });
    }
  }

  Future<void> _detectCurrentLocation() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      final detected = ll.LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _detectedCurrentLocation = detected;
      });

      _mapController.move(detected, 16);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to detect current location. Check GPS permissions.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _recenterRoute() {
    if (widget.route.isNotEmpty) {
      _mapController.move(widget.route.last, 15);
      return;
    }
    final fallback = ll.LatLng(widget.initialLatitude, widget.initialLongitude);
    _mapController.move(fallback, 14);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final latestCurrent =
        (widget.currentLatitude != null && widget.currentLongitude != null)
            ? ll.LatLng(widget.currentLatitude!, widget.currentLongitude!)
            : _detectedCurrentLocation;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: ll.LatLng(widget.initialLatitude, widget.initialLongitude),
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.sales_tracking_app',
            ),
            if (widget.route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.route,
                    strokeWidth: 5,
                    color: primaryColor,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                ...widget.otherMarkers.map(
                  (marker) => Marker(
                    point: marker.point,
                    width: 42,
                    height: 42,
                    child: Icon(Icons.location_pin, color: marker.color, size: 34),
                  ),
                ),
                if (latestCurrent != null)
                  Marker(
                    point: latestCurrent,
                    width: 52,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(Icons.my_location, color: primaryColor, size: 28),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            children: [
              _MapActionButton(
                icon: _isLocating ? Icons.gps_not_fixed : Icons.my_location,
                tooltip: 'Detect current location',
                onTap: _isLocating ? null : _detectCurrentLocation,
              ),
              const SizedBox(height: 10),
              _MapActionButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Recenter map',
                onTap: _recenterRoute,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

class TrackerMapMarker {
  const TrackerMapMarker({required this.point, required this.color});

  final ll.LatLng point;
  final Color color;
}
