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
}
