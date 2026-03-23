import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class LocationNameText extends StatefulWidget {
  const LocationNameText({
    super.key,
    required this.latitude,
    required this.longitude,
    this.style,
    this.prefix,
  });

  final double latitude;
  final double longitude;
  final TextStyle? style;
  final String? prefix;

  @override
  State<LocationNameText> createState() => _LocationNameTextState();
}

class _LocationNameTextState extends State<LocationNameText> {
  static final Map<String, String> _cache = {};

  late Future<String> _futureName;

  @override
  void initState() {
    super.initState();
    _futureName = _resolve();
  }

  @override
  void didUpdateWidget(covariant LocationNameText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude;
    if (changed) {
      _futureName = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _futureName,
      builder: (context, snapshot) {
        final name = snapshot.data ?? 'Resolving location...';
        final text = widget.prefix == null ? name : '${widget.prefix}$name';
        return Text(
          text,
          style: widget.style,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Future<String> _resolve() async {
    final key =
        '${widget.latitude.toStringAsFixed(4)}_${widget.longitude.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final places = await placemarkFromCoordinates(
        widget.latitude,
        widget.longitude,
      );

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
          final label = chunks.join(', ');
          _cache[key] = label;
          return label;
        }
      }
    } catch (_) {
      // Fall back to coordinates when reverse-geocoding fails.
    }

    final fallback =
        '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}';
    _cache[key] = fallback;
    return fallback;
  }
}
