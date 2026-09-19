/// Central place for table names, storage buckets, and other fixed strings,
/// so a rename only ever has to happen in one place. Matches the schema in
/// /supabase/01_extensions_and_tables.sql exactly.
class AppConstants {
  AppConstants._();

  // Postgres tables
  static const String profilesTable = 'profiles';
  static const String categoriesTable = 'categories';
  static const String itemsTable = 'items';
  static const String itemImagesTable = 'item_images';
  static const String matchesTable = 'matches';
  static const String messagesTable = 'messages';
  static const String contactMessagesTable = 'contact_messages';
  static const String claimsTable = 'claims';
  static const String reportsTable = 'reports';
  static const String ratingsTable = 'ratings';

  // Postgres RPC functions (see 02_functions_and_triggers.sql)
  static const String matchItemsFunction = 'match_items';
  static const String nearbyItemsFunction = 'nearby_items';

  // Storage buckets (see 04_storage_setup.sql)
  static const String itemImagesBucket = 'item-images';
  static const String avatarsBucket = 'avatars';

  // On-device model — see assets/models/README.md
  static const String tfliteModelAsset =
      'assets/models/mobilenet_v2_embedder.tflite';
  static const String tfliteLabelsAsset = 'assets/models/imagenet_labels.txt';
  static const int embeddingDimension = 1280;
}
