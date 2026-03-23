import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef OnLocationPoint = Future<void> Function(Position position);
typedef OnConnectivityState = Future<void> Function(bool isOnline);

class DeviceTrackingService {
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  Future<void> start({
    required OnLocationPoint onLocationPoint,
    required OnConnectivityState onConnectivityState,
  }) async {
    await _ensureLocationPermission();

    final locationSettings = _buildLocationSettings();

    final results = await Connectivity().checkConnectivity();
    await onConnectivityState(!_isOffline(results));

    final initialPosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
      ),
    );
    await onLocationPoint(initialPosition);

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      onConnectivityState(!_isOffline(results));
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      onLocationPoint(position);
    });
  }

  LocationSettings _buildLocationSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 3,
        intervalDuration: Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Location tracking active',
          notificationText: 'Tracking route while checked in.',
          enableWakeLock: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: 3,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    return const LocationSettings(
      accuracy: accuracy,
      distanceFilter: 3,
    );
  }

  Future<void> stop() async {
    try {
      await _positionSubscription?.cancel();
    } catch (_) {
      // Ignore cancellation races from platform stream teardown.
    }
    _positionSubscription = null;

    try {
      await _connectivitySubscription?.cancel();
    } catch (_) {
      // Ignore cancellation races from platform stream teardown.
    }
    _connectivitySubscription = null;
  }

  bool _isOffline(List<ConnectivityResult> results) {
    if (results.isEmpty) return true;
    return results.every((result) => result == ConnectivityResult.none);
  }

  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are not granted.');
    }
  }
}
