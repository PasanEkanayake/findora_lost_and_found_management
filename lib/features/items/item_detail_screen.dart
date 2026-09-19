import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../chat/chat_screen.dart';
import '../matches/data/matches_providers.dart';
import '../../core/providers/auth_providers.dart';
import 'data/item_model.dart';
import 'data/items_providers.dart';

/// Full detail for one item — reachable by tapping a card in the feed or
/// the map. This was a real gap before Phase 8: there was no way to see a
/// full description or all of an item's photos, and nowhere for the
/// "Report" action to live.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report this item',
            onPressed: () => _showReportDialog(context, ref),
          ),
        ],
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't load this item.")),
        data: (item) => _ItemDetailBody(item: item),
      ),
      bottomNavigationBar: itemAsync.maybeWhen(
        data: (item) => _ContactBar(item: item),
        orElse: () => null,
      ),
    );
  }

  Future<void> _showReportDialog(BuildContext context, WidgetRef ref) async {
    const reasons = [
      'Spam or scam',
      'Inappropriate content',
      'Doesn\'t look like a real item',
      'Other',
    ];
    var selected = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Report this item'),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (value) => setState(() => selected = value!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final reason in reasons)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(reason),
                    value: reason,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(itemsRepositoryProvider).fileReport(itemId: itemId, reason: selected);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — a moderator will take a look.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't submit the report. Try again.")),
      );
    }
  }
}

/// Sticky bottom action for someone else's item — deliberately doesn't
/// offer a generic "message poster" shortcut, since chat is gated behind
/// a confirmed AI match by design (see Phase 5/7 in the README): sharing
/// contact info before a match is verified is exactly what that gate
/// exists to prevent. Instead this looks for a *real* confirmed match
/// connecting one of the viewer's own items to this one, and only offers
/// to open that chat if one genuinely exists.
class _ContactBar extends ConsumerWidget {
  const _ContactBar({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    if (myId == null || item.userId == myId) return const SizedBox.shrink();

    final matchesAsync = ref.watch(matchesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: matchesAsync.when(
          loading: () => const SizedBox(
            height: 52,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (matches) {
            final confirmed = matches.where(
              (m) => m.matchedItemId == item.id && m.status == 'confirmed',
            );
            final relevantMatch = confirmed.isEmpty ? null : confirmed.first;

            if (relevantMatch != null) {
              return FilledButton.icon(
                onPressed: () => context.push(
                  '/chat',
                  extra: ChatScreenArgs(
                    matchId: relevantMatch.matchId,
                    otherUserId: item.userId,
                    otherItemTitle: item.title,
                    myItemId: relevantMatch.myItemId,
                    matchedItemId: item.id,
                    matchedItemType: item.type,
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message about this item'),
              );
            }

            return OutlinedButton.icon(
              onPressed: () => context.push('/post-item'),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                item.isLost ? 'I think I found this — report it' : 'This might be mine — report it',
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ItemDetailBody extends StatefulWidget {
  const _ItemDetailBody({required this.item});

  final ItemModel item;

  @override
  State<_ItemDetailBody> createState() => _ItemDetailBodyState();
}

class _ItemDetailBodyState extends State<_ItemDetailBody> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final statusColor = item.isLost ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return ListView(
      children: [
        if (item.imageUrls.isEmpty)
          Container(
            height: 260,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(Icons.image_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              SizedBox(
                height: 260,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    for (final url in item.imageUrls)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: theme.colorScheme.surfaceContainerHighest),
                      ),
                  ],
                ),
              ),
              if (item.imageUrls.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < item.imageUrls.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _currentPage ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.isLost ? 'LOST' : 'FOUND',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (item.categoryName != null) ...[
                    const SizedBox(width: 8),
                    Chip(label: Text(item.categoryName!)),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(item.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (item.description != null && item.description!.isNotEmpty) ...[
                Text(item.description!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              if (item.locationLabel != null)
                _DetailRow(icon: Icons.location_on_outlined, text: item.locationLabel!),
              _DetailRow(
                icon: Icons.schedule,
                text: DateFormat.yMMMd().add_jm().format(item.createdAt),
              ),
              if (item.locationLabel != null) ...[
                const SizedBox(height: 16),
                _LocationPreview(itemId: item.id),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationPreview extends ConsumerWidget {
  const _LocationPreview({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordsAsync = ref.watch(itemCoordinatesProvider(itemId));

    return coordsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (coords) {
        if (coords == null) return const SizedBox.shrink();
        final position = LatLng(coords.latitude, coords.longitude);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 140,
            child: IgnorePointer(
              // A preview, not an interactive map — the full map view
              // (Browse tab) is where panning/zooming actually matters.
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: position, zoom: 14),
                markers: {Marker(markerId: const MarkerId('item'), position: position)},
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                liteModeEnabled: true,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
