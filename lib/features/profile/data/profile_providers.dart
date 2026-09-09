import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_repository.dart';
import 'profile_model.dart';
import 'profile_repository.dart';
import 'report_model.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return const ProfileRepository();
});

/// autoDispose + `ref.invalidate(myProfileProvider)` after a new rating
/// comes in — used by ProfileScreen to show the real rating/count and by
/// MainShell-adjacent screens to gate the admin entry point on `isAdmin`.
final myProfileProvider = FutureProvider.autoDispose<ProfileModel>((ref) {
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return const AdminRepository();
});

final openReportsProvider = FutureProvider.autoDispose<List<ReportModel>>((ref) {
  return ref.watch(adminRepositoryProvider).fetchOpenReports();
});