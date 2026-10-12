import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'profile_model.dart';
import 'rating_model.dart';

class ProfileRepository {
  const ProfileRepository();

  /// Fetches the `profiles` row for the signed-in user — the fields
  /// Supabase Auth's `User` object doesn't carry, like rating and the
  /// admin flag. Assumes `handle_new_user` already created this row.
  Future<ProfileModel> fetchMyProfile() async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from(AppConstants.profilesTable)
        .select()
        .eq('id', userId)
        .single();
    // Phone number and push token live in their own owner-only table
    // (supabase/17_harden_policies.sql). No row yet = nothing saved yet.
    // If the table isn't there (migration not applied) the profile still
    // loads, just without a phone number.
    Map<String, dynamic>? private;
    try {
      private = await supabase
          .from(AppConstants.profilePrivateTable)
          .select('phone')
          .eq('id', userId)
          .maybeSingle();
    } catch (_) {
      private = null;
    }
    return ProfileModel.fromMap({...row, ...?private});
  }

  Future<void> updateProfile({String? fullName, String? phone}) async {
    final userId = supabase.auth.currentUser!.id;
    if (fullName != null) {
      await supabase
          .from(AppConstants.profilesTable)
          .update({'full_name': fullName}).eq('id', userId);
    }
    if (phone != null) {
      // Upsert: first-time savers have no profile_private row yet. An empty
      // string clears the number.
      await supabase.from(AppConstants.profilePrivateTable).upsert({
        'id': userId,
        'phone': phone.isEmpty ? null : phone,
      });
    }
  }

  /// Browse another country's posts for [days] days (1–30), after which the
  /// home country comes back by itself. The database enforces the limits.
  Future<void> setTemporaryCountry(String countryCode, int days) async {
    await supabase.from(AppConstants.profilesTable).update({
      'temp_country_code': countryCode,
      'temp_country_until': DateTime.now().toUtc().add(Duration(days: days)).toIso8601String(),
    }).eq('id', supabase.auth.currentUser!.id);
  }

  Future<void> clearTemporaryCountry() async {
    await supabase.from(AppConstants.profilesTable).update({
      'temp_country_code': null,
      'temp_country_until': null,
    }).eq('id', supabase.auth.currentUser!.id);
  }

  /// Saves the HOME country (where this person lives). Changing it again is
  /// limited to once every 30 days — the database refuses earlier changes with
  /// a message saying when the next one is possible.
  Future<void> updateCountry(String countryCode) async {
    await supabase
        .from(AppConstants.profilesTable)
        .update({'country_code': countryCode}).eq('id', supabase.auth.currentUser!.id);
  }

  /// Uploads to the `avatars` bucket under `{user_id}/...` (matching the
  /// storage policy in 04_storage_setup.sql), then saves the resulting
  /// public URL onto the profile row. Returns the new URL.
  Future<String> uploadAvatar(File file) async {
    final userId = supabase.auth.currentUser!.id;
    final extension = file.path.split('.').last;
    final storagePath = '$userId/${const Uuid().v4()}.$extension';

    await supabase.storage.from(AppConstants.avatarsBucket).upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    final publicUrl =
        supabase.storage.from(AppConstants.avatarsBucket).getPublicUrl(storagePath);

    await supabase
        .from(AppConstants.profilesTable)
        .update({'avatar_url': publicUrl}).eq('id', userId);

    return publicUrl;
  }

  /// Every rating the signed-in user received or gave, newest first —
  /// backed by the `my_ratings()` RPC. Only the two people involved in a
  /// rating can read it (see supabase/13_returned_items_and_ratings.sql).
  Future<List<RatingModel>> fetchMyRatings() async {
    final rows = await supabase.rpc('my_ratings');
    return (rows as List<dynamic>)
        .map((row) => RatingModel.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Calls request_account_deletion() (supabase/09_account_deletion.sql,
  /// redefined in 16_release_email_on_delete.sql) — see those files for
  /// exactly what it does (soft-deletes their items, scrubs personal
  /// fields, anonymises the auth row so the email can be used again after
  /// a cooldown, blocks future sign-in) and why it's not a real
  /// `delete from auth.users`. Doesn't sign the caller
  /// out itself — ProfileScreen does that right after this returns, so
  /// the current session ends immediately rather than lingering until
  /// the ban takes effect on next token refresh.
  Future<void> requestAccountDeletion() async {
    await supabase.rpc('request_account_deletion');
  }
}
