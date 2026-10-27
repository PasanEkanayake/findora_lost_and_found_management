/// Central place for table names, storage buckets, and other fixed strings,
/// so a rename only ever has to happen in one place. Matches the schema in
/// /supabase/01_extensions_and_tables.sql exactly.
class AppConstants {
  AppConstants._();

  // Postgres tables
  static const String profilesTable = 'profiles';
  // Phone number + push token: owner-only, split out of `profiles` by
  // supabase/17_harden_policies.sql so other people's API calls can't read them.
  static const String profilePrivateTable = 'profile_private';
  // A found item's expected proof-of-ownership answer — owner-only
  // (supabase/24_proof_questions.sql).
  static const String itemPrivateTable = 'item_private';
  static const String categoriesTable = 'categories';
  static const String itemsTable = 'items';
  static const String itemImagesTable = 'item_images';
  static const String matchesTable = 'matches';
  static const String messagesTable = 'messages';
  static const String contactMessagesTable = 'contact_messages';
  static const String claimsTable = 'claims';
  static const String reportsTable = 'reports';
  static const String userBlocksTable = 'user_blocks';
  static const String userReportsTable = 'user_reports';
  static const String appealsTable = 'appeals';
  static const String moderationLogTable = 'moderation_log';
  static const String ratingsTable = 'ratings';
  static const String notificationsTable = 'notifications';

  // Postgres RPC functions (see 02_functions_and_triggers.sql)
  static const String matchItemsFunction = 'match_items';
  static const String nearbyItemsFunction = 'nearby_items';

  // Storage buckets (see 04_storage_setup.sql)
  static const String itemImagesBucket = 'item-images';
  // Edge Function that makes list-size thumbnails (supabase/functions/make-thumbnails).
  static const String makeThumbnailsFunction = 'make-thumbnails';
  static const String avatarsBucket = 'avatars';
  // Private — photos sent inside chats (see supabase/30_chat_photos.sql).
  static const String chatImagesBucket = 'chat-images';

  // On-device model — see assets/models/README.md
  static const String tfliteModelAsset =
      'assets/models/mobilenet_v2_embedder.tflite';
  static const String tfliteLabelsAsset = 'assets/models/imagenet_labels.txt';
  static const int embeddingDimension = 1280;
}
