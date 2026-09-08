import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/ml/tflite_classifier.dart';
import '../../../core/supabase/supabase_client.dart';
import 'category_model.dart';
import 'item_model.dart';

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

  Future<List<ItemModel>> fetchOpenItems() async {
    final rows = await supabase
        .from(AppConstants.itemsTable)
        .select('*, categories(name), item_images(image_url)')
        .eq('status', 'open')
        .order('created_at', ascending: false);
    return rows.map(ItemModel.fromMap).toList();
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
        })
        .select()
        .single();

    final itemId = itemRow['id'] as String;

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
        // NOTE: inserting a Dart List<double> directly into a pgvector
        // column works via PostgREST in the common case, since a JSON
        // array's text form matches pgvector's own `[0.1,0.2,...]` input
        // format — but this is untested against a live project in this
        // sandbox, so verify it once you have a real device and model.
        if (classification != null) ...{
          'embedding': classification.embedding,
          'predicted_label': classification.label,
          'confidence': classification.confidence,
        },
      });
    }

    return itemId;
  }
}
