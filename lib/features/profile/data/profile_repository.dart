import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import 'profile_model.dart';

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
    return ProfileModel.fromMap(row);
  }

  Future<void> updateProfile({String? fullName, String? phone}) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from(AppConstants.profilesTable).update({
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    }).eq('id', userId);
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

  /// Calls request_account_deletion() (supabase/09_account_deletion.sql)
  /// — see that function's own doc for exactly what it does (soft-deletes
  /// their items, scrubs personal fields, blocks future sign-in) and why
  /// it's not a real `delete from auth.users`. Doesn't sign the caller
  /// out itself — ProfileScreen does that right after this returns, so
  /// the current session ends immediately rather than lingering until
  /// the ban takes effect on next token refresh.
  Future<void> requestAccountDeletion() async {
    await supabase.rpc('request_account_deletion');
  }
}
