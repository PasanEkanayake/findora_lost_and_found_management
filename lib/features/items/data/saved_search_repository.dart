import '../../../core/location/countries.dart';
import '../../../core/supabase/supabase_client.dart';

/// A search the person asked to be alerted about (supabase/28_saved_searches.sql).
class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.countryCode,
    required this.active,
    required this.createdAt,
    this.query,
    this.categoryId,
    this.categoryName,
    this.type,
  });

  final String id;
  final String? query;
  final String? categoryId;
  final String? categoryName;

  /// 'lost' | 'found' | null for both.
  final String? type;
  final String countryCode;

  /// Alerts on/off, without deleting the search.
  final bool active;
  final DateTime createdAt;

  /// How a search reads in lists and snack bars: `"wallet" · Keys · Found · 🇱🇰 Sri Lanka`.
  static String describe({
    String? query,
    String? categoryName,
    String? type,
    required String countryCode,
  }) {
    final parts = <String>[
      if (query != null && query.trim().isNotEmpty) '"${query.trim()}"',
      if (categoryName != null && categoryName.isNotEmpty) categoryName,
      if (type == 'lost') 'Lost posts',
      if (type == 'found') 'Found posts',
      countryLabel(countryCode).isEmpty ? countryCode : countryLabel(countryCode),
    ];
    return parts.join(' · ');
  }

  String get label => describe(
        query: query,
        categoryName: categoryName,
        type: type,
        countryCode: countryCode,
      );

  factory SavedSearch.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    return SavedSearch(
      id: map['id'] as String,
      query: map['query'] as String?,
      categoryId: map['category_id'] as String?,
      categoryName: category?['name'] as String?,
      type: map['type'] as String?,
      countryCode: map['country_code'] as String,
      active: map['active'] as bool,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class SavedSearchRepository {
  const SavedSearchRepository();

  static const _table = 'saved_searches';

  Future<List<SavedSearch>> fetchAll() async {
    final rows = await supabase
        .from(_table)
        .select('*, categories(name)')
        .order('created_at', ascending: false);
    return rows.map(SavedSearch.fromMap).toList();
  }

  /// Saves a search. The database enforces the limit of 10, refuses an exact
  /// duplicate (SQLSTATE 23505) and requires words or a category.
  Future<void> create({
    String? query,
    String? categoryId,
    String? type,
    required String countryCode,
  }) async {
    final words = query?.trim();
    await supabase.from(_table).insert({
      'user_id': supabase.auth.currentUser!.id,
      'query': (words == null || words.isEmpty) ? null : words,
      'category_id': categoryId,
      'type': type,
      'country_code': countryCode,
    });
  }

  Future<void> setActive(String id, bool active) async {
    await supabase.from(_table).update({'active': active}).eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }
}
