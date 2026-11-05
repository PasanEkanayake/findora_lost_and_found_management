/// How recent a post must be to show in Browse ("Posted within").
enum FeedWindow {
  any('Any time', null),
  day('Last 24 hours', Duration(hours: 24)),
  week('Last 7 days', Duration(days: 7)),
  month('Last 30 days', Duration(days: 30));

  const FeedWindow(this.label, this.duration);

  final String label;
  final Duration? duration;

  /// The oldest creation time that still passes the filter, or null for
  /// [any]. Computed when a request is made (not stored), so a "last 24
  /// hours" list that stays open is always relative to now.
  DateTime? cutoff([DateTime? now]) {
    final span = duration;
    if (span == null) return null;
    return (now ?? DateTime.now()).subtract(span);
  }
}

/// The order Browse lists posts in.
enum FeedSort {
  newest('Newest first'),
  oldest('Oldest first'),

  /// Closest to the phone's current position first; posts without a location
  /// come last. Needs location permission.
  nearest('Nearest to me');

  const FeedSort(this.label);

  final String label;
}
