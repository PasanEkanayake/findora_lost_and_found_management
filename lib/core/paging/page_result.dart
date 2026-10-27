/// How many rows a paged list shows at first, and how many more each
/// "Show more" adds.
const int kListPageSize = 20;

/// One page of a list that grows with a "Show more" button.
///
/// These lists ask the server for the newest N rows (N grows by
/// [kListPageSize] each time) rather than for "the rows after the last one":
/// a refresh then simply re-reads the same N rows, so a match that was just
/// decided or a report that was just dismissed moves or disappears correctly
/// and the list never collapses back to its first page.
///
/// Callers fetch `limit + 1` rows; the extra one is only a signal that there
/// is more, and is dropped here.
class PageResult<T> {
  const PageResult({required this.items, required this.hasMore});

  final List<T> items;

  /// True when the server had more than [items] to give.
  final bool hasMore;

  factory PageResult.fromFetched(List<T> fetched, int limit) {
    return PageResult(
      items: fetched.length > limit ? fetched.sublist(0, limit) : fetched,
      hasMore: fetched.length > limit,
    );
  }
}
