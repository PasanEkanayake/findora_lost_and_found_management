import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/tflite_classifier.dart';
import '../../../core/supabase/supabase_client.dart';
import 'category_model.dart';
import 'feed_options.dart';
import 'item_model.dart';
import 'nearby_item_model.dart';
import 'returned_item_model.dart';
import 'thumbnails.dart';

/// pgvector's own text input format is a plain bracketed, comma-separated
/// list — e.g. "[0.1,0.2,0.3]" — accepted by a `vector` column's input
/// parser regardless of how PostgREST would otherwise have encoded a raw
/// Dart List`<`double`>` in the request body. See the two call sites' comments
/// for why this matters.
String _pgvectorLiteral(List<double> values) => '[${values.join(',')}]';

/// Data access for everything under `items`/`item_images`/`categories`.
/// A post's coordinates as the caller is allowed to see them.
typedef ItemCoordinates = ({double latitude, double longitude, bool isExact});

class ItemsRepository {
  const ItemsRepository();

  Future<List<CategoryModel>> fetchCategories() async {
    final rows = await supabase
        .from(AppConstants.categoriesTable)
        .select()
        .order('name');
    return rows.map(CategoryModel.fromMap).toList();
  }

  /// The columns the feed needs — everything [ItemModel.fromMap] reads, and
  /// deliberately NOT `*`: that would also download each post's 384-number
  /// text embedding and its raw location for every card.
  static const _feedColumns = 'id, user_id, type, status, title, description, '
      'category_id, location_label, created_at, event_time, country_code';

  /// Search text goes into a PostgREST filter string, where `,` `(` `)` `"`
  /// and `\` have meaning (and `%` `_` `*` act as wildcards), so a search
  /// for `a,user_id.eq.x` would otherwise change the query itself. Those
  /// characters are replaced with spaces; null means "no search".
  static String? cleanSearchTerm(String? raw) {
    final cleaned = raw?.replaceAll(RegExp(r'[,()"\\%_*]'), ' ').trim();
    return (cleaned == null || cleaned.isEmpty) ? null : cleaned;
  }

  /// One page of open posts, newest first. [type], [categoryId] and
  /// [searchQuery] are applied server-side. Pass the `createdAt` of the last
  /// post you have as [before] to get the page after it (keyset paging —
  /// unlike offset paging it doesn't skip or repeat posts when new ones are
  /// added while someone scrolls). Each post comes with only its FIRST photo.
  Future<List<ItemModel>> fetchOpenItems({
    String? categoryId,
    String? searchQuery,
    String? type,
    String? country,
    FeedWindow window = FeedWindow.any,
    bool oldestFirst = false,
    DateTime? before,
    DateTime? after,
    int limit = 20,
  }) async {
    var query = supabase
        .from(AppConstants.itemsTable)
        .select('$_feedColumns, categories(name), item_images(image_url, thumb_url)')
        .eq('status', 'open')
        .filter('deleted_at', 'is', null);

    if (type != null) {
      query = query.eq('type', type);
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    // The feed is per country (supabase/26_country.sql).
    if (country != null) {
      query = query.eq('country_code', country);
    }
    final term = cleanSearchTerm(searchQuery);
    if (term != null) {
      query = query.or('title.ilike.%$term%,description.ilike.%$term%');
    }
    final cutoff = window.cutoff();
    if (cutoff != null) {
      query = query.gte('created_at', cutoff.toUtc().toIso8601String());
    }
    // Keyset paging in whichever direction the list runs: "before" for newest
    // first, "after" for oldest first.
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    if (after != null) {
      query = query.gt('created_at', after.toUtc().toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: oldestFirst)
        .order('created_at', ascending: true, referencedTable: 'item_images')
        .limit(1, referencedTable: 'item_images')
        .limit(limit);
    return rows.map(ItemModel.fromMap).toList();
  }

  /// One page of posts ordered by distance from ([lat], [lng]), nearest first;
  /// posts without a location come last. The order comes from the database
  /// (`feed_nearest_ids()` in supabase/28_saved_searches.sql), which returns
  /// ids; the posts themselves are then loaded and put in that order. Paged by
  /// [offset] (distance has no stable cursor like a timestamp does).
  Future<List<ItemModel>> fetchNearestItems({
    required double lat,
    required double lng,
    String? categoryId,
    String? searchQuery,
    String? type,
    String? country,
    FeedWindow window = FeedWindow.any,
    int limit = 20,
    int offset = 0,
  }) async {
    final idRows = await supabase.rpc('feed_nearest_ids', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_country': country,
      'p_category_id': categoryId,
      'p_search': cleanSearchTerm(searchQuery),
      'p_type': type,
      'p_since': window.cutoff()?.toUtc().toIso8601String(),
      'p_limit': limit,
      'p_offset': offset,
    });
    final ids = [for (final row in (idRows as List<dynamic>)) (row as Map<String, dynamic>)['id'] as String];
    if (ids.isEmpty) return const [];

    final rows = await supabase
        .from(AppConstants.itemsTable)
        .select('$_feedColumns, categories(name), item_images(image_url, thumb_url)')
        .inFilter('id', ids)
        .order('created_at', ascending: true, referencedTable: 'item_images')
        .limit(1, referencedTable: 'item_images');

    final byId = {for (final row in rows) row['id'] as String: ItemModel.fromMap(row)};
    // Back into the database's order; a post that vanished in between is skipped.
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  /// "N lost · N found" for the current search/category (see `feed_counts()`
  /// in supabase/19_indexes.sql). Null if the function isn't there yet, so
  /// the feed still works — just without the totals — until it's applied.
  Future<({int lost, int found})?> fetchFeedCounts({
    String? categoryId,
    String? searchQuery,
    String? country,
    FeedWindow window = FeedWindow.any,
  }) async {
    try {
      final rows = await supabase.rpc('feed_counts', params: {
        'p_category_id': categoryId,
        'p_search': cleanSearchTerm(searchQuery),
        'p_country': country,
        'p_since': window.cutoff()?.toUtc().toIso8601String(),
      });
      final row = (rows as List<dynamic>).first as Map<String, dynamic>;
      return (lost: (row['lost_count'] as num).toInt(), found: (row['found_count'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  /// Calls the `nearby_items()` RPC for the map view — a PostGIS radius
  /// search, not the same query as [fetchOpenItems] (which has no location
  /// filter at all).
  Future<List<NearbyItemModel>> fetchNearbyItems({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  }) async {
    final rows = await supabase.rpc(
      AppConstants.nearbyItemsFunction,
      params: {
        'center_lat': latitude,
        'center_lng': longitude,
        'radius_meters': radiusMeters,
      },
    );
    return (rows as List<dynamic>)
        .map((row) => NearbyItemModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<ItemModel> fetchItemById(String id) async {
    final row = await supabase
        .from(AppConstants.itemsTable)
        // profiles!items_user_id_fkey, not a bare profiles(...): since
        // 13_returned_items_and_ratings.sql added items.returned_with_user_id
        // (also a foreign key to profiles), PostgREST can no longer infer
        // which relationship a plain `profiles(...)` embed means and
        // rejects the whole query (PGRST201 — "more than one relationship
        // was found"). This is the poster's profile specifically, not
        // whoever the item was returned with, hence the user_id-named
        // constraint rather than the returned_with_user_id one.
        .select(
          '*, categories(name), item_images(image_url, thumb_url), '
          'profiles!items_user_id_fkey(full_name, username)',
        )
        .eq('id', id)
        .filter('deleted_at', 'is', null)
        .single();
    return ItemModel.fromMap(row);
  }

  /// Null if the item has no location set at all, rather than (0, 0) —
  /// callers should treat null as "don't show a map", not "map of the
  /// middle of the ocean".
  ///
  /// The post's OWNER gets the exact spot they pinned ([ItemCoordinates.isExact]
  /// is true — the edit screen needs it); everyone else gets the approximate
  /// public one (false), which the app draws as an area, not a pin.
  /// See supabase/33_approximate_locations.sql.
  Future<ItemCoordinates?> fetchItemCoordinates(String itemId) async {
    final rows = await supabase.rpc(
      'get_item_coordinates',
      params: {'p_item_id': itemId},
    );
    final list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    if (row['latitude'] == null || row['longitude'] == null) return null;
    return (
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      // An older database (before 33_approximate_locations.sql) has no such
      // column — and returned the exact spot to everyone.
      isExact: (row['is_exact'] as bool?) ?? true,
    );
  }

  /// Every post the signed-in user still has *in play* — open, matched or
  /// claimed — used by "My reported items" in ProfileScreen. Two kinds are
  /// left out on purpose: their own deleted posts (deleting is meant to
  /// remove a post from view for the person who deleted it too), and posts
  /// that have been **returned**, which live in their own "Returned items"
  /// section instead (see [fetchMyReturnedItems]) so this list only shows
  /// things still being worked on.
  Future<List<ItemModel>> fetchMyItems() async {
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from(AppConstants.itemsTable)
        .select('*, categories(name), item_images(image_url, thumb_url)')
        .eq('user_id', userId)
        .neq('status', 'resolved')
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false)
        // A person is limited to 20 new posts a day, so this is far more than
        // anyone has; it only guards against an unbounded download.
        .limit(200);
    return rows.map(ItemModel.fromMap).toList();
  }

  /// The signed-in user's returned posts, each with the post it was
  /// returned with — the "Returned items" section of the profile. Backed
  /// by the `my_returned_items()` RPC; a returned post is only ever
  /// visible to its two owners (see supabase/13_returned_items_and_ratings.sql).
  Future<List<ReturnedItemModel>> fetchMyReturnedItems() async {
    final rows = await supabase.rpc('my_returned_items');
    return (rows as List<dynamic>)
        .map((row) => ReturnedItemModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Soft-delete: marks the item inactive rather than removing the row.
  /// RLS no longer grants `delete` on `items` at all (see
  /// 08_soft_delete.sql) — every "remove a post" path, owner or admin,
  /// goes through this `deleted_at` flag instead, so the underlying data
  /// always stays recoverable (a manual `update ... set deleted_at = null`
  /// in the SQL editor is all it'd take to undo one). The existing
  /// "users can update their own items" RLS policy already covers this
  /// update — no new policy was needed.
  ///
  /// Every read this repository does (fetchOpenItems, fetchMyItems,
  /// fetchItemById) already excludes `deleted_at is not null` rows, so a
  /// soft-deleted item disappears from the app immediately, same as a
  /// hard delete would have — the only difference is the row survives.
  /// Keeps a post up for another full lifetime (60 days), or brings an expired
  /// one back: the `renew_item()` function (supabase/35_post_expiry.sql).
  /// Returns the new expiry. Throws (with a readable message for
  /// [friendlyDatabaseError]) if the post isn't the caller's or can't be renewed.
  Future<DateTime> renewItem(String itemId) async {
    final result = await supabase.rpc('renew_item', params: {'p_item_id': itemId});
    return DateTime.parse(result as String).toLocal();
  }

  Future<void> deleteItem(String itemId) async {
    await supabase
        .from(AppConstants.itemsTable)
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', itemId);
  }

  /// Edits an existing item's text/category/location/time — not its type
  /// (lost/found): changing what something *is* mid-post would flip every
  /// existing match's meaning, so that's a bigger, separate feature
  /// (effectively "delete and repost"). Photos are edited separately, with
  /// [addPhotosToItem] / [removeItemImages], so existing matches/chats
  /// referencing this item stay valid throughout.
  ///
  /// RLS-wise this is covered by the same "users can update their own
  /// items" policy `deleteItem` uses — no new policy needed. Whether the
  /// caller actually owns [itemId] is enforced there, not in this method.
  Future<void> updateItem({
    required String itemId,
    required String title,
    String? description,
    String? categoryId,
    double? latitude,
    double? longitude,
    String? locationLabel,
    DateTime? eventTime,
    bool textChanged = false,
    List<double>? textEmbedding,
    bool isFound = false,
    String? proofQuestion,
    String? proofAnswer,
    String? countryCode,
  }) async {
    await supabase.from(AppConstants.itemsTable).update({
      'title': title,
      if (countryCode != null) 'country_code': countryCode,
      // Only FOUND posts carry a proof question; for lost posts the column is
      // left alone. Empty clears it.
      if (isFound)
        'proof_question':
            (proofQuestion == null || proofQuestion.trim().isEmpty) ? null : proofQuestion.trim(),
      'description': description,
      // When the wording changed, the stored text embedding describes the OLD
      // wording, so it must be replaced — with the fresh one, or with null
      // when the AI service didn't answer (null makes matching fall back to
      // comparing the actual words, which beats comparing the old meaning).
      // Left out entirely when the text didn't change, so an unrelated edit
      // never throws away a good embedding.
      if (textChanged)
        'text_embedding': textEmbedding == null ? null : _pgvectorLiteral(textEmbedding),
      'category_id': categoryId,
      if (latitude != null && longitude != null)
        'location': 'POINT($longitude $latitude)',
      'location_label': locationLabel,
      'event_time': eventTime?.toIso8601String(),
    }).eq('id', itemId);

    // proofAnswer == null means "didn't load / not touched" — leave it alone.
    // An empty string clears it.
    if (isFound && proofAnswer != null) {
      final answer = proofAnswer.trim();
      if (answer.isEmpty) {
        await supabase.from(AppConstants.itemPrivateTable).delete().eq('item_id', itemId);
      } else {
        await supabase
            .from(AppConstants.itemPrivateTable)
            .upsert({'item_id': itemId, 'proof_answer': answer});
      }
    }
  }

  /// The expected answer to this post's proof question. Only the post's owner
  /// can read it (row-level security); anyone else gets null.
  Future<String?> fetchProofAnswer(String itemId) async {
    try {
      final row = await supabase
          .from(AppConstants.itemPrivateTable)
          .select('proof_answer')
          .eq('item_id', itemId)
          .maybeSingle();
      return row?['proof_answer'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> fileReport({required String itemId, required String reason}) async {
    await supabase.from(AppConstants.reportsTable).insert({
      'item_id': itemId,
      'reporter_id': supabase.auth.currentUser!.id,
      'reason': reason,
    });
  }

  /// This user's own photos (on open, non-deleted items) that were
  /// uploaded **without** an embedding — the ones AI matching has never
  /// been able to see.
  ///
  /// That happens whenever on-device classification failed at post time
  /// (see PostItemScreen's `_classifyAllPhotos`, which deliberately
  /// doesn't block posting on it), including every photo posted before
  /// the output-order fix in `TfliteClassifier`. Own photos only: RLS
  /// (supabase/11_realtime_and_matching_fixes.sql) lets a user write
  /// embeddings for their own photos and nobody else's, and the embedding
  /// has to come from a device anyway.
  Future<List<({String id, String url})>> fetchMyImagesMissingEmbeddings() async {
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from(AppConstants.itemImagesTable)
        .select('id, image_url, items!inner(user_id, status, deleted_at)')
        .filter('embedding', 'is', null)
        .eq('items.user_id', userId)
        .eq('items.status', 'open')
        .filter('items.deleted_at', 'is', null);
    return rows
        .map((row) => (id: row['id'] as String, url: row['image_url'] as String))
        .toList();
  }

  /// Asks the server to make thumbnails (the `make-thumbnails` Edge Function —
  /// see supabase/functions/make-thumbnails/README.md) for every photo of
  /// [itemId], or for the photos in [imageIds]. Both only work on the caller's
  /// own posts.
  ///
  /// Best effort by design: never throws, and a failure just means lists keep
  /// showing the full photo, which every list query falls back to.
  Future<void> requestThumbnails({String? itemId, List<String>? imageIds}) async {
    try {
      await supabase.functions.invoke(
        AppConstants.makeThumbnailsFunction,
        body: {
          if (itemId != null) 'item_id': itemId,
          if (imageIds != null) 'image_ids': imageIds,
        },
      );
    } catch (e) {
      debugPrint('Thumbnail request failed (lists use the full photo): $e');
    }
  }

  /// Ids of up to [limit] of the signed-in user's photos that have no
  /// thumbnail yet, oldest first — see `thumbnailBackfillProvider`.
  Future<List<String>> fetchMyImageIdsMissingThumbnails({int limit = 30}) async {
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from(AppConstants.itemImagesTable)
        .select('id, items!inner(user_id, deleted_at)')
        .filter('thumb_url', 'is', null)
        .eq('items.user_id', userId)
        .filter('items.deleted_at', 'is', null)
        .order('created_at', ascending: true)
        .limit(limit);
    return rows.map((row) => row['id'] as String).toList();
  }

  /// Downloads one already-uploaded photo, embeds it on-device, and saves
  /// the result onto its existing `item_images` row.
  ///
  /// The database side is `item_images_record_matches_on_embedding`
  /// (supabase/11_realtime_and_matching_fixes.sql): filling in an
  /// embedding that was null fires the same match search a fresh upload
  /// would have, so matches for this photo appear without any further
  /// call from here.
  ///
  /// Throws (rather than silently succeeding) if the update touched zero
  /// rows — with RLS, an `update` that isn't permitted doesn't error, it
  /// just matches nothing, and that would otherwise look exactly like
  /// success.
  Future<void> embedExistingImage({
    required String imageId,
    required String imageUrl,
    required TfliteClassifier classifier,
  }) async {
    final response =
        await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Photo download failed (HTTP ${response.statusCode})');
    }
    final result = await classifier.classifyBytes(response.bodyBytes);

    final updated = await supabase
        .from(AppConstants.itemImagesTable)
        .update({
          'embedding': _pgvectorLiteral(result.embedding),
          'predicted_label': result.label,
          'confidence': result.confidence,
        })
        .eq('id', imageId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        "The database didn't accept this photo's embedding — "
        'run supabase/11_realtime_and_matching_fixes.sql in the Supabase SQL Editor.',
      );
    }
  }

  /// Inserts the `items` row, uploads each photo to Storage under
  /// `{user_id}/{item_id}/...`, then inserts one `item_images` row per
  /// photo pointing at its public URL. Returns the new item's id.
  ///
  /// [classifications], when provided, must be the same length and order
  /// as [photos] — each entry's embedding/label/confidence (or `null`, if
  /// on-device classification wasn't available for that photo) is stored
  /// alongside that photo's row, which is what powers the pgvector
  /// similarity search in `match_items()`.
  Future<String> createItem({
    required String type,
    required String title,
    required List<File> photos,
    List<ClassificationResult?>? classifications,
    String? description,
    String? categoryId,
    double? latitude,
    double? longitude,
    String? locationLabel,
    DateTime? eventTime,
    List<double>? textEmbedding,
    String? proofQuestion,
    String? proofAnswer,
    required String countryCode,
  }) async {
    final userId = supabase.auth.currentUser!.id;

    final itemRow = await supabase
        .from(AppConstants.itemsTable)
        .insert({
          'user_id': userId,
          'type': type,
          'title': title,
          'description': description,
          'category_id': categoryId,
          // Postgres's geography type accepts WKT text directly via an
          // implicit cast — no need for st_makepoint()/RPC round-trips
          // just to insert a point.
          if (latitude != null && longitude != null)
            'location': 'POINT($longitude $latitude)',
          'location_label': locationLabel,
          if (eventTime != null) 'event_time': eventTime.toIso8601String(),
          // Included directly in the initial insert (rather than a
          // follow-up update) whenever it resolved in time, so it's
          // already present when the item_images insert below fires
          // record_matches_for_image — meaning brand-new items get
          // text-similarity-aware matches from their very first photo,
          // not just on a later rescore. See TextEmbeddingService's doc
          // for when this ends up null instead.
          //
          // Sent as pgvector's own text format ("[0.1,0.2,...]"), the
          // same reasoning as 'location' above: PostgREST round-trips a
          // Dart List<double> as a JSON array, and whether Postgres
          // implicitly casts a JSON array to `vector` depends on
          // PostgREST/Postgres version and isn't guaranteed — sending
          // the column's own native text representation directly sidesteps
          // that entirely, the same way 'POINT(...)' does for `geography`.
          if (textEmbedding != null) 'text_embedding': _pgvectorLiteral(textEmbedding),
          'country_code': countryCode,
          if (proofQuestion != null && proofQuestion.trim().isNotEmpty)
            'proof_question': proofQuestion.trim(),
        })
        .select()
        .single();

    final itemId = itemRow['id'] as String;

    // The expected answer goes in a separate owner-only table. If it can't be
    // saved the post still exists — the finder can add it by editing.
    if (proofAnswer != null && proofAnswer.trim().isNotEmpty) {
      try {
        await supabase
            .from(AppConstants.itemPrivateTable)
            .upsert({'item_id': itemId, 'proof_answer': proofAnswer.trim()});
      } catch (e) {
        debugPrint('Could not save the proof answer: $e');
      }
    }

    try {
      await addPhotosToItem(
        itemId: itemId,
        photos: photos,
        classifications: classifications,
      );
    } catch (_) {
      // The post exists but its photos didn't make it. Withdraw it, so that
      // trying again doesn't leave a duplicate photo-less post behind.
      try {
        await supabase
            .from(AppConstants.itemsTable)
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', itemId);
      } catch (_) {}
      rethrow;
    }

    return itemId;
  }

  /// Uploads each photo to Storage under `{user_id}/{item_id}/...` and
  /// inserts one `item_images` row per photo pointing at its public URL.
  /// Used both when an item is first posted and when photos are added to an
  /// existing one.
  ///
  /// [classifications], when provided, must be the same length and order
  /// as [photos] — each entry's embedding/label/confidence (or `null`, if
  /// on-device classification wasn't available for that photo) is stored
  /// alongside that photo's row, which is what powers the pgvector
  /// similarity search in `match_items()`. Inserting a row with an
  /// embedding fires the match search for it right away
  /// (`item_images_record_matches`), so adding a photo to an existing item
  /// can produce new matches immediately.
  Future<void> addPhotosToItem({
    required String itemId,
    required List<File> photos,
    List<ClassificationResult?>? classifications,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final bucket = supabase.storage.from(AppConstants.itemImagesBucket);

    // Upload the files a few at a time (each retried on a flaky connection),
    // then insert the database rows in the ORIGINAL order — "the first photo"
    // is whichever row was created first, so the order must not depend on
    // which upload happened to finish first.
    final paths = List<String?>.filled(photos.length, null);
    try {
      const concurrency = 3;
      for (var start = 0; start < photos.length; start += concurrency) {
        final end = (start + concurrency).clamp(0, photos.length);
        await Future.wait([
          for (var i = start; i < end; i++)
            () async {
              final extension = photos[i].path.split('.').last;
              final storagePath = '$userId/$itemId/${const Uuid().v4()}.$extension';
              await _withRetry(() => bucket.upload(storagePath, photos[i]));
              paths[i] = storagePath;
            }(),
        ]);
      }

      for (var i = 0; i < photos.length; i++) {
        final classification =
            (classifications != null && i < classifications.length) ? classifications[i] : null;
        final publicUrl = bucket.getPublicUrl(paths[i]!);

        await _withRetry(() => supabase.from(AppConstants.itemImagesTable).insert({
              'item_id': itemId,
              'image_url': publicUrl,
              if (classification != null) ...{
                // Sent as pgvector's own text format ("[0.1,0.2,...]") — see
                // _pgvectorLiteral. record_matches_for_image skips matching
                // entirely whenever `new.embedding is null`, so a malformed or
                // null vector here means this photo is never matched, with no
                // error anywhere. If matches don't appear, check the column
                // (`select embedding from item_images order by created_at desc
                // limit 5;`) to confirm it's a real vector.
                'embedding': _pgvectorLiteral(classification.embedding),
                'predicted_label': classification.label,
                'confidence': classification.confidence,
              },
            }));
      }
      // Lists will show a small version of each photo. It's made by the server
      // (an Edge Function) a moment after this; until then — or if that fails —
      // lists simply use the full photo, so nothing waits on it.
      unawaited(requestThumbnails(itemId: itemId));
    } catch (_) {
      // Don't leave orphaned files behind for photos that never got a row.
      // Best effort: the failure being reported is the original one.
      final uploaded = [for (final path in paths) if (path != null) path];
      if (uploaded.isNotEmpty) {
        try {
          await bucket.remove(uploaded);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Runs [operation], retrying twice more (after 0.4 s, then 0.8 s) when it
  /// fails the way a flaky mobile connection does. A 4xx answer from Storage
  /// (file too large, not allowed, no permission) is the server saying no —
  /// retrying can't change that — so it is raised straight away.
  Future<T> _withRetry<T>(Future<T> Function() operation) async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      try {
        return await operation();
      } on StorageException catch (e) {
        final status = int.tryParse(e.statusCode ?? '');
        final refused = status != null && status >= 400 && status < 500;
        if (refused || attempt == maxAttempts) rethrow;
      } catch (_) {
        if (attempt == maxAttempts) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << (attempt - 1))));
    }
  }

  /// The photos currently saved on [itemId], oldest first, each with the
  /// `item_images.id` needed to remove it.
  Future<List<({String id, String url})>> fetchItemImages(String itemId) async {
    final rows = await supabase
        .from(AppConstants.itemImagesTable)
        .select('id, image_url')
        .eq('item_id', itemId)
        .order('created_at', ascending: true);
    return rows
        .map((row) => (id: row['id'] as String, url: row['image_url'] as String))
        .toList();
  }

  /// Removes photos from an item: the `item_images` row first (so the photo
  /// disappears from the app and stops being matched immediately), then the
  /// file in Storage on a best-effort basis.
  ///
  /// This is a real delete, unlike posts (which are soft-deleted — see
  /// [deleteItem]): a photo is the poster's own content and a leftover
  /// file would just sit in Storage forever. RLS ("users can delete images
  /// from their own items", and the matching Storage policy) restricts
  /// this to the owner. Matches already created from a removed photo are
  /// left as they are; the other person's app simply shows whichever photo
  /// the item has now.
  Future<void> removeItemImages(List<({String id, String url})> images) async {
    for (final image in images) {
      await supabase.from(AppConstants.itemImagesTable).delete().eq('id', image.id);

      final storagePath = _storagePathFromPublicUrl(image.url);
      if (storagePath == null) continue;
      try {
        // The photo and its thumbnail (removing one that doesn't exist is fine).
        await supabase.storage
            .from(AppConstants.itemImagesBucket)
            .remove([storagePath, thumbnailPathFor(storagePath)]);
      } catch (_) {
        // The row is already gone, which is what matters to the person. A
        // stray file is harmless, so don't fail the whole edit over it.
      }
    }
  }

  /// `.../storage/v1/object/public/item-images/{user}/{item}/{file}` ->
  /// `{user}/{item}/{file}`; null if the URL isn't one of ours.
  String? _storagePathFromPublicUrl(String url) {
    final marker = '/${AppConstants.itemImagesBucket}/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    final path = url.substring(index + marker.length);
    return Uri.decodeComponent(path.split('?').first);
  }
}
