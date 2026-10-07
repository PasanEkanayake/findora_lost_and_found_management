import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/tflite_classifier.dart';
import '../../../core/supabase/supabase_client.dart';
import 'category_model.dart';
import 'item_model.dart';
import 'nearby_item_model.dart';
import 'returned_item_model.dart';

/// pgvector's own text input format is a plain bracketed, comma-separated
/// list — e.g. "[0.1,0.2,0.3]" — accepted by a `vector` column's input
/// parser regardless of how PostgREST would otherwise have encoded a raw
/// Dart List`<`double`>` in the request body. See the two call sites' comments
/// for why this matters.
String _pgvectorLiteral(List<double> values) => '[${values.join(',')}]';

/// Data access for everything under `items`/`item_images`/`categories`.
class ItemsRepository {
  const ItemsRepository();

  Future<List<CategoryModel>> fetchCategories() async {
    final rows = await supabase
        .from(AppConstants.categoriesTable)
        .select()
        .order('name');
    return rows.map(CategoryModel.fromMap).toList();
  }

  /// [categoryId] and [searchQuery] are applied server-side rather than by
  /// filtering the fetched list in Dart, so this scales past however many
  /// items fit comfortably in memory on a phone.
  Future<List<ItemModel>> fetchOpenItems({String? categoryId, String? searchQuery}) async {
    var query = supabase
        .from(AppConstants.itemsTable)
        .select('*, categories(name), item_images(image_url)')
        .eq('status', 'open')
        .filter('deleted_at', 'is', null);

    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    final term = searchQuery?.trim();
    if (term != null && term.isNotEmpty) {
      query = query.or('title.ilike.%$term%,description.ilike.%$term%');
    }

    final rows = await query.order('created_at', ascending: false);
    return rows.map(ItemModel.fromMap).toList();
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
          '*, categories(name), item_images(image_url), '
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
  Future<({double latitude, double longitude})?> fetchItemCoordinates(String itemId) async {
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
        .select('*, categories(name), item_images(image_url)')
        .eq('user_id', userId)
        .neq('status', 'resolved')
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false);
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
  }) async {
    await supabase.from(AppConstants.itemsTable).update({
      'title': title,
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
        })
        .select()
        .single();

    final itemId = itemRow['id'] as String;

    await addPhotosToItem(
      itemId: itemId,
      photos: photos,
      classifications: classifications,
    );

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

    for (var i = 0; i < photos.length; i++) {
      final file = photos[i];
      final classification =
          (classifications != null && i < classifications.length) ? classifications[i] : null;

      final extension = file.path.split('.').last;
      final storagePath = '$userId/$itemId/${const Uuid().v4()}.$extension';

      await supabase.storage
          .from(AppConstants.itemImagesBucket)
          .upload(storagePath, file);

      final publicUrl = supabase.storage
          .from(AppConstants.itemImagesBucket)
          .getPublicUrl(storagePath);

      await supabase.from(AppConstants.itemImagesTable).insert({
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
      });
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
        await supabase.storage.from(AppConstants.itemImagesBucket).remove([storagePath]);
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
