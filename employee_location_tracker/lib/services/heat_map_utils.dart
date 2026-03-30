import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/route_point.dart';

/// Heat map data point for visualization
class HeatMapPoint {
  HeatMapPoint({
    required this.latitude,
    required this.longitude,
    required this.intensity, // 0.0 to 1.0
  });

  final double latitude;
  final double longitude;
  final double intensity;
}

/// Utility class for heat map processing
class HeatMapUtils {
  /// Generate heat map data from route points
  /// Groups points into grid cells and calculates intensity based on point density
  static List<HeatMapPoint> generateHeatMapFromRoutes(
    List<RoutePoint> allRoutePoints, {
    double gridSize = 0.002, // ~200m grid cells
  }) {
    if (allRoutePoints.isEmpty) return [];

    // Group points by grid cell
    final Map<String, List<RoutePoint>> gridCells = {};

    for (final point in allRoutePoints) {
      final gridLat = (point.latitude / gridSize).floor() * gridSize;
      final gridLng = (point.longitude / gridSize).floor() * gridSize;
      final key = '$gridLat,$gridLng';

      gridCells.putIfAbsent(key, () => []).add(point);
    }

    // Find max count for normalization
    final maxCount = gridCells.values.fold<int>(
      0,
      (max, points) => points.length > max ? points.length : max,
    );

    if (maxCount == 0) return [];

    // Convert grid cells to heat map points
    return gridCells.entries.map((entry) {
      final coords = entry.key.split(',');
      final lat = double.parse(coords[0]);
      final lng = double.parse(coords[1]);
      final intensity = entry.value.length / maxCount;

      return HeatMapPoint(latitude: lat, longitude: lng, intensity: intensity);
    }).toList();
  }

  /// Convert heat map points to Google Maps Markers with color gradient
  static Set<Marker> heatMapPointsToMarkers(List<HeatMapPoint> points) {
    return points.asMap().entries.map((entry) {
      final index = entry.key;
      final point = entry.value;

      // Color gradient: green -> yellow -> red based on intensity
      final color = _getHeatMapColor(point.intensity);

      return Marker(
        markerId: MarkerId('heatmap_$index'),
        position: LatLng(point.latitude, point.longitude),
        infoWindow: InfoWindow(
          title:
              'Traffic Intensity: ${(point.intensity * 100).toStringAsFixed(0)}%',
          snippet:
              '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(_colorToHue(color)),
      );
    }).toSet();
  }

  /// Public heat map color accessor for non-Google map renderers.
  static Color getHeatMapColor(double intensity) => _getHeatMapColor(intensity);

  /// Get color for heat map intensity
  static Color _getHeatMapColor(double intensity) {
    // Green (0) -> Yellow (0.5) -> Red (1.0)
    if (intensity < 0.5) {
      final t = intensity * 2;
      return Color.lerp(Colors.green, Colors.yellow, t)!;
    } else {
      final t = (intensity - 0.5) * 2;
      return Color.lerp(Colors.yellow, Colors.red, t)!;
    }
  }

  /// Convert Color to BitmapDescriptor hue value
  static double _colorToHue(Color color) {
    // Simplified HSV conversion for marker hue (0-360)
    // Extract ARGB components from the color's int value
    final int colorValue = color.toARGB32();
    final int r = (colorValue >> 16) & 0xFF;
    final int g = (colorValue >> 8) & 0xFF;
    final int b = colorValue & 0xFF;

    final double rf = r / 255.0;
    final double gf = g / 255.0;
    final double bf = b / 255.0;

    final double max = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final double min = [rf, gf, bf].reduce((a, b) => a < b ? a : b);

    double hue = 0;
    if (max != min) {
      if (max == rf) {
        hue = (60 * (gf - bf) / (max - min) + 360) % 360;
      } else if (max == gf) {
        hue = (60 * (bf - rf) / (max - min) + 120) % 360;
      } else {
        hue = (60 * (rf - gf) / (max - min) + 240) % 360;
      }
    }

    return hue;
  }

  /// Get employee activity metrics
  static Map<String, dynamic> getActivityMetrics(
    List<RoutePoint> points, {
    Duration timeWindow = const Duration(hours: 8),
  }) {
    if (points.isEmpty) {
      return {
        'totalPoints': 0,
        'activeTime': const Duration(),
        'avgSpeedMps': 0.0,
        'maxSpeedMps': 0.0,
        'totalDistance': 0.0,
      };
    }

    // Calculate time span
    final firstTime = points.first.timestamp;
    final lastTime = points.last.timestamp;
    final timeSpan = lastTime.difference(firstTime);

    // Calculate average and max speed
    final speeds = points
        .map((p) => p.speedMetersPerSecond ?? 0.0)
        .where((s) => s > 0)
        .toList();
    final avgSpeed = speeds.isEmpty
        ? 0.0
        : speeds.reduce((a, b) => a + b) / speeds.length;
    final maxSpeed = speeds.isEmpty
        ? 0.0
        : speeds.reduce((a, b) => (a > b) ? a : b);

    // Calculate total distance (rough estimate from speed)
    double totalDistance = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final distance = _calculateDistance(
        p1.latitude,
        p1.longitude,
        p2.latitude,
        p2.longitude,
      );
      totalDistance += distance;
    }

    return {
      'totalPoints': points.length,
      'activeTime': timeSpan,
      'avgSpeedMps': avgSpeed,
      'maxSpeedMps': maxSpeed,
      'totalDistance': totalDistance,
    };
  }

  /// Calculate distance between two coordinates (Haversine formula)
  static double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusM = 6371000; // Earth radius in meters
    final double dLat = _toRad(lat2 - lat1);
    final double dLng = _toRad(lng2 - lng1);

    final double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2));
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusM * c;
  }

  static double _toRad(double degrees) => degrees * (3.141592653589793 / 180);
}
