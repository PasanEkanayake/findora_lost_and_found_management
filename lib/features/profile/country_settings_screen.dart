import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/location/countries.dart';
import '../../core/location/country_picker.dart';
import '../../core/widgets/confirm_dialog.dart';
import 'data/profile_model.dart';
import 'data/profile_providers.dart';

/// Where this person is: the HOME country (for good) and, optionally, a
/// TEMPORARY country for a trip.
///
/// Browse shows posts from one country at a time, and match suggestions never
/// cross countries, so this decides what a person sees. The limits keep it
/// honest (enforced by the database, see supabase/27_country_settings.sql):
///  * the home country can be changed once every 30 days;
///  * a temporary country lasts 1–30 days and then ends by itself;
///  * posts are not affected — each post keeps the country of the place it
///    was lost or found.
class CountrySettingsScreen extends ConsumerWidget {
  const CountrySettingsScreen({super.key});

  static const _durations = [3, 7, 14, 30];

  Future<void> _changeHome(BuildContext context, WidgetRef ref, ProfileModel profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showCountryPicker(
      context,
      selected: profile.countryCode,
      title: 'Your home country',
    );
    if (picked == null || picked == profile.countryCode || !context.mounted) return;

    // The very first choice is free; after that there is a 30-day wait, so
    // make sure they mean it.
    if (profile.countryCode != null) {
      final ok = await showConfirmDialog(
        context,
        icon: Icons.public,
        title: 'Change your country to ${countryName(picked)}?',
        message: 'This is for moving. You can only change your home country once every '
            '30 days. If you are just travelling, use "Browse another country for a while" '
            'instead.',
        confirmLabel: 'Change country',
      );
      if (!ok) return;
    }
    try {
      await ref.read(profileRepositoryProvider).updateCountry(picked);
      ref.invalidate(myProfileProvider);
      messenger.showSnackBar(SnackBar(content: Text('Your country is now ${countryName(picked)}.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyDatabaseError(e, fallback: "Couldn't change your country. Try again."),
          ),
        ),
      );
    }
  }

  Future<void> _startTrip(BuildContext context, WidgetRef ref, ProfileModel profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showCountryPicker(
      context,
      title: 'Which country are you visiting?',
    );
    if (picked == null || !context.mounted) return;
    if (picked == profile.countryCode) {
      messenger.showSnackBar(
        const SnackBar(content: Text("That's already your home country.")),
      );
      return;
    }

    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var selected = 7;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Browse ${countryName(picked)} for how long?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in _durations)
                      ChoiceChip(
                        label: Text('$d days'),
                        selected: selected == d,
                        onSelected: (_) => setState(() => selected = d),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your home country comes back by itself afterwards. You can end the trip '
                  'earlier at any time.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('Start'),
              ),
            ],
          ),
        );
      },
    );
    if (days == null) return;

    try {
      await ref.read(profileRepositoryProvider).setTemporaryCountry(picked, days);
      ref.invalidate(myProfileProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            friendlyDatabaseError(e, fallback: "Couldn't start that. Try again."),
          ),
        ),
      );
    }
  }

  Future<void> _endTrip(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileRepositoryProvider).clearTemporaryCountry();
      ref.invalidate(myProfileProvider);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't end the trip. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myProfileProvider);
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(title: const Text('Country')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load your profile.")),
        data: (profile) {
          final home = profile.countryCode;
          final trip = profile.activeTempCountry;
          final tripUntil = profile.tempCountryUntil;
          final nextChange = profile.nextCountryChangeAt;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Browse shows posts from one country at a time, and matches are only made '
                'between posts in the same country.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your home country', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Text(
                        home == null ? 'Not set yet' : countryLabel(home),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Where you live. New posts start here, and Browse shows its posts '
                        'when you are not travelling.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: nextChange != null
                            ? null
                            : () => _changeHome(context, ref, profile),
                        child: Text(home == null ? 'Choose country' : 'Change home country'),
                      ),
                      if (nextChange != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'You can change it again from ${dateFormat.format(nextChange.toLocal())} '
                          '(once every 30 days).',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Travelling?', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (trip != null && tripUntil != null) ...[
                        Text(
                          'Browsing ${countryLabel(trip)} until '
                          '${dateFormat.format(tripUntil.toLocal())}',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Then ${home == null ? "your home country" : countryName(home)} '
                          'comes back by itself.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _endTrip(context, ref),
                          child: const Text('End trip now'),
                        ),
                      ] else ...[
                        Text(
                          'See posts from another country for a while, for up to 30 days. '
                          'Your home country is not changed.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _startTrip(context, ref, profile),
                          child: const Text('Browse another country for a while'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Good to know: each post keeps the country of the place where the item was '
                'lost or found, whatever country you are browsing.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }
}
