import 'package:findora/core/paging/page_result.dart';
import 'package:findora/features/matches/data/match_model.dart';
import 'package:findora/features/matches/data/matches_repository.dart';

/// One match as the fake "database" holds it: each owner's own decision
/// (null | 'confirmed' | 'dismissed'), from which the status is derived by the
/// same rules as `decide_match()` in supabase/31_two_sided_confirmation.sql.
class FakeMatch {
  FakeMatch({
    required this.id,
    required this.title,
    this.score = 0.8,
    DateTime? createdAt,
    this.myDecision,
    this.otherDecision,
  }) : createdAt = createdAt ?? DateTime(2026, 10, 1);

  final String id;
  final String title; // the other person's item
  final double score;
  final DateTime createdAt;
  String? myDecision;
  String? otherDecision;

  String get status {
    if (myDecision == 'dismissed' || otherDecision == 'dismissed') return 'dismissed';
    if (myDecision == 'confirmed' && otherDecision == 'confirmed') return 'confirmed';
    return 'pending';
  }
}

/// A MatchesRepository backed by a list in memory. It filters, orders, limits
/// and decides the way the database does, so a screen driven by it behaves
/// like the real app — including "waiting for the other person".
class FakeMatchesRepository implements MatchesRepository {
  FakeMatchesRepository(this.matches);

  final List<FakeMatch> matches;

  /// When true, any filter other than "All" matches nothing — to exercise the
  /// "No matches with this filter" state without modelling every signal.
  bool emptyWhenFiltered = false;

  /// Every page request the app made, in order (to check paging and filters).
  final List<({String section, MatchFilter filter, String? itemId, int limit})> requests = [];

  /// Every decision the app sent, in order.
  final List<({String matchId, String decision})> decisions = [];

  FakeMatch byId(String id) => matches.firstWhere((m) => m.id == id);

  /// The other person confirms (or dismisses) — something that happens on
  /// their phone, between this user's refreshes.
  void otherDecides(String id, String decision) => byId(id).otherDecision = decision;

  bool _inSection(FakeMatch m, String section) => switch (section) {
        'pending' => m.status == 'pending' && m.myDecision != 'confirmed',
        'waiting' => m.status == 'pending' && m.myDecision == 'confirmed',
        'decided' => m.status != 'pending',
        'confirmed' => m.status == 'confirmed',
        _ => true,
      };

  MatchModel _model(FakeMatch m) {
    final status = m.status;
    return MatchModel(
      matchId: m.id,
      myItemId: 'mine-${m.id}',
      myItemTitle: 'Black wallet',
      matchedItemId: 'theirs-${m.id}',
      matchedItemTitle: m.title,
      matchedItemType: 'found',
      matchedItemUserId: 'other-user',
      similarityScore: m.score,
      status: status,
      createdAt: m.createdAt,
      myDecision: m.myDecision,
      otherConfirmed: m.otherDecision == 'confirmed',
      reopenable: status == 'dismissed'
          ? (m.myDecision == 'dismissed' || (m.myDecision == null && m.otherDecision == null))
          : true,
    );
  }

  @override
  Future<PageResult<MatchModel>> fetchMatchesPage({
    String section = 'all',
    MatchFilter filter = MatchFilter.all,
    String? itemId,
    int limit = kListPageSize,
  }) async {
    requests.add((section: section, filter: filter, itemId: itemId, limit: limit));

    final rows = matches
        .where((m) => _inSection(m, section))
        .where((m) => !(emptyWhenFiltered && filter != MatchFilter.all))
        .toList()
      ..sort((a, b) {
        if (section == 'pending' || section == 'waiting') {
          final byScore = b.score.compareTo(a.score);
          if (byScore != 0) return byScore;
        }
        return b.createdAt.compareTo(a.createdAt);
      });

    // Like the real repository: ask for one more than needed to learn whether
    // there is a next page.
    final fetched = rows.take(limit + 1).map(_model).toList();
    return PageResult.fromFetched(fetched, limit);
  }

  @override
  Future<String> decide(String matchId, String decision) async {
    decisions.add((matchId: matchId, decision: decision));
    final m = byId(matchId);
    m.myDecision = decision == 'pending' ? null : decision;
    return m.status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
