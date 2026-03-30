import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter state for location tracking dashboard
class LocationFilter {
  const LocationFilter({
    this.showOnlineOnly = false,
    this.showCheckedInOnly = false,
    this.searchQuery = '',
  });

  final bool showOnlineOnly;
  final bool showCheckedInOnly;
  final String searchQuery;

  LocationFilter copyWith({
    bool? showOnlineOnly,
    bool? showCheckedInOnly,
    String? searchQuery,
  }) {
    return LocationFilter(
      showOnlineOnly: showOnlineOnly ?? this.showOnlineOnly,
      showCheckedInOnly: showCheckedInOnly ?? this.showCheckedInOnly,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// State notifier for location filter
class LocationFilterNotifier extends StateNotifier<LocationFilter> {
  LocationFilterNotifier() : super(const LocationFilter());

  void setOnlineFilter(bool value) => state = state.copyWith(showOnlineOnly: value);
  void setCheckedInFilter(bool value) => state = state.copyWith(showCheckedInOnly: value);
  void setSearchQuery(String query) => state = state.copyWith(searchQuery: query);
  void reset() => state = const LocationFilter();
}

/// Provider for location filter
final locationFilterProvider = StateNotifierProvider<LocationFilterNotifier, LocationFilter>((ref) {
  return LocationFilterNotifier();
});
