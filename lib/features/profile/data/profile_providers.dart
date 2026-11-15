import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/location/countries.dart';
import '../../../core/paging/page_result.dart';
import 'appeal_model.dart';
import 'moderated_item_model.dart';
import 'moderation_log_entry.dart';
import 'moderation_repository.dart';
import '../../../core/supabase/supabase_client.dart';

import 'admin_repository.dart';
import 'profile_model.dart';
import 'profile_repository.dart';
import 'rating_model.dart';
import 'report_model.dart';
import 'user_report_model.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const ProfileRepository();
});

/// autoDispose + `ref.invalidate(myProfileProvider)` after a new rating
/// comes in — used by ProfileScreen to show the real rating/count and by
/// MainShell-adjacent screens to gate the admin entry point on `isAdmin`.
final myProfileProvider = FutureProvider.autoDispose<ProfileModel>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

/// The country whose posts this person sees (and that new posts default to):
/// a temporary "travelling" country while it lasts, otherwise their home
/// country, otherwise the region of the phone's language settings
/// ("en_LK" -> "LK"), otherwise null (no country filter). Safe to read before
/// the profile has loaded.
final myCountryProvider = Provider.autoDispose<String?>((ref) {
  final profile = ref.watch(myProfileProvider).value;
  final temporary = profile?.activeTempCountry;
  if (temporary != null && isKnownCountry(temporary)) return temporary;
  final home = profile?.countryCode;
  if (home != null && isKnownCountry(home)) return home;
  final device = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  return isKnownCountry(device) ? device : null;
});

final myRatingsProvider = FutureProvider.autoDispose<List<RatingModel>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyRatings();
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return const AdminRepository();
});

/// Open reports about people / about posts, newest first. The family
/// parameter is how many to show (grows with "Show more"); invalidating the
/// bare provider refreshes whatever is on screen.
final openUserReportsProvider =
    FutureProvider.autoDispose.family<PageResult<UserReportModel>, int>((ref, limit) {
  return ref.watch(adminRepositoryProvider).fetchOpenUserReports(limit: limit);
});

final openReportsProvider =
    FutureProvider.autoDispose.family<PageResult<ReportModel>, int>((ref, limit) {
  return ref.watch(adminRepositoryProvider).fetchOpenReports(limit: limit);
});

/// Open appeals and the audit log, newest/oldest as the repository says. Same
/// "limit grows with Show more" shape as the report queues above.
final openAppealsProvider =
    FutureProvider.autoDispose.family<PageResult<AppealModel>, int>((ref, limit) {
  return ref.watch(adminRepositoryProvider).fetchOpenAppeals(limit: limit);
});

final moderationLogProvider =
    FutureProvider.autoDispose.family<PageResult<ModerationLogEntry>, int>((ref, limit) {
  return ref.watch(adminRepositoryProvider).fetchModerationLog(limit: limit);
});

final moderationRepositoryProvider = Provider<ModerationRepository>((ref) {
  return const ModerationRepository();
});

/// The signed-in user's own posts that moderation hid or removed (empty for
/// nearly everyone). Invalidate after sending an appeal.
final myModeratedItemsProvider = FutureProvider.autoDispose<List<ModeratedItemModel>>((ref) {
  return ref.watch(moderationRepositoryProvider).fetchMyModeratedItems();
});

/// How established someone is on Findora — shown to a finder deciding on a
/// claim, since a long-standing, well-rated account is a signal and a brand-new
/// one with no ratings is worth a little extra care. Reads only the public
/// rating columns of `profiles`.
class PersonStanding {
  const PersonStanding({
    required this.rating,
    required this.ratingCount,
    required this.memberSince,
  });

  final double rating;
  final int ratingCount;
  final DateTime memberSince;

  /// e.g. "★ 4.8 (5 ratings) · member since Sep 2026" or
  /// "new to Findora · no ratings yet".
  String describe() {
    final since = DateFormat.yMMM().format(memberSince.toLocal());
    if (ratingCount == 0) return 'no ratings yet · member since $since';
    final noun = ratingCount == 1 ? 'rating' : 'ratings';
    return '★ ${rating.toStringAsFixed(1)} ($ratingCount $noun) · member since $since';
  }
}

final personStandingProvider =
    FutureProvider.autoDispose.family<PersonStanding?, String>((ref, userId) async {
  try {
    final row = await supabase
        .from('profiles')
        .select('rating, rating_count, created_at')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return PersonStanding(
      rating: (row['rating'] as num).toDouble(),
      ratingCount: (row['rating_count'] as num).toInt(),
      memberSince: DateTime.parse(row['created_at'] as String),
    );
  } catch (_) {
    return null;
  }
});
