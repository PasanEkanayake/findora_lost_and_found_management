import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../chat/chat_screen.dart';
import '../contact/contact_chat_screen.dart';
import '../contact/data/contact_providers.dart';
import '../matches/data/matches_providers.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/item_photo.dart';
import '../../core/widgets/new_badge.dart';
import 'data/item_model.dart';
import 'data/items_providers.dart';

/// Full detail for one item — reachable by tapping a card in the feed or
/// the map.
class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(
        actions: [
          itemAsync.maybeWhen(
            data: (item) => item.userId == myId
                ? _OwnerMenu(item: item)
                : IconButton(
                    icon: const Icon(Icons.flag_outlined),
                    tooltip: 'Report this item',
                    onPressed: () => _showReportDialog(context, ref),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          // The previous version of this screen showed only a static
          // "Couldn't load this item." with no way to retry and no way to
          // tell *why* — every failure looked identical, whether the item
          // genuinely doesn't exist, isn't visible any more (e.g. it was
          // returned — see supabase/13_returned_items_and_ratings.sql — and
          // this account isn't one of its two owners), or something else
          // entirely broke. Logging the real error and showing it on
          // screen, plus a retry button, turns "it's just broken" into
          // something that can actually be diagnosed.
          debugPrint('ItemDetailScreen($itemId) failed to load: $error\n$stackTrace');
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 40, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  const Text(
                    "Couldn't load this item.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "This can happen if the post was removed, or if it's no "
                    'longer visible to your account (for example, once an '
                    'item is returned it stays visible only to the two '
                    'people involved).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(itemDetailProvider(itemId)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        },
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

/// Owner-only overflow menu — "Edit post" and "Delete post", kept as a
/// menu rather than bare icon buttons so a future "Mark as resolved"
/// action has an obvious place to live too without crowding the app bar
/// with more icons.
class _OwnerMenu extends ConsumerWidget {
  const _OwnerMenu({required this.item});

  final ItemModel item;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.delete_outline,
      title: 'Delete this post?',
      message: 'This removes "${item.title}" from Findora — nobody else will be able to see '
          "it or get matched against it anymore. Any chats you've already had about it stay "
          'accessible.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(itemsRepositoryProvider).deleteItem(item.id);
      ref.invalidate(itemsFeedProvider);
      ref.invalidate(myItemsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Post deleted.')));
      context.pop();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't delete this post. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (value) {
        if (value == 'edit') context.push('/edit-item', extra: item);
        if (value == 'delete') _delete(context, ref);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 12),
              Text('Edit post'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 12),
              Text('Delete post', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sticky bottom action for someone else's item. Two distinct paths,
/// intentionally kept apart:
///   - A confirmed AI match connecting one of the viewer's own items to
///     this one → the verified claim/chat flow (ChatScreen).
///   - Otherwise → a plain "Contact poster" button (new — see
///     supabase/06_contact_messaging.sql), plus the existing "I think
///     this might be mine" shortcut into posting a matching report.
class _ContactBar extends ConsumerWidget {
  const _ContactBar({required this.item});

  final ItemModel item;

  Future<void> _startContact(BuildContext context, WidgetRef ref) async {
    try {
      final threadId = await ref.read(contactRepositoryProvider).startThread(item.id);
      if (!context.mounted) return;
      context.push(
        '/contact-chat',
        extra: ContactChatArgs(
          threadId: threadId,
          itemTitle: item.title,
          otherUserName: item.posterName ?? 'Findora user',
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't start that conversation.")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    if (myId == null || item.userId == myId) return const SizedBox.shrink();

    // A returned post is only reachable by its two owners (anyone else is
    // blocked by row-level security), and the exchange is finished — so there
    // is nothing left to contact anyone about.
    if (item.status == 'resolved') {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Icon(Icons.task_alt, color: theme.colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This item has been returned. Find your chat under Profile → Returned items.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final matchesAsync = ref.watch(matchesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: matchesAsync.when(
          loading: () => const SizedBox(
            height: 52,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) =>
              _ContactOnlyActions(item: item, onContact: () => _startContact(context, ref)),
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

            return _ContactOnlyActions(item: item, onContact: () => _startContact(context, ref));
          },
        ),
      ),
    );
  }
}

class _ContactOnlyActions extends StatelessWidget {
  const _ContactOnlyActions({required this.item, required this.onContact});

  final ItemModel item;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: onContact,
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text('Contact ${item.posterName ?? 'poster'}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push('/post-item'),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(
            item.isLost ? 'I think I found this — report it' : 'This might be mine — report it',
          ),
        ),
      ],
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
      padding: EdgeInsets.zero,
      children: [
        if (item.imageUrls.isEmpty)
          const SizedBox(
            height: 280,
            child: ItemPhotoPlaceholder(showLabel: true),
          )
        else
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              SizedBox(
                height: 280,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    for (final url in item.imageUrls)
                      Container(
                        // Fills whatever space BoxFit.contain leaves empty
                        // around a non-16:9 photo, so showing the whole
                        // image (not cropping it to fill the carousel)
                        // doesn't look like a rendering glitch.
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                          placeholder: (context, url) =>
                              Container(color: theme.colorScheme.surfaceContainerHighest),
                        ),
                      ),
                  ],
                ),
              ),
              // A subtle scrim at the very bottom of the carousel keeps the
              // page-dots legible over a bright photo without dimming the
              // photo itself everywhere else.
              if (item.imageUrls.length > 1) ...[
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
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
            ],
          ),

        // The content "sheet" overlaps the carousel slightly with rounded
        // top corners — a common pattern for photo-led detail screens that
        // reads as more considered than content just starting flush below
        // the images.
        Transform.translate(
          offset: const Offset(0, -16),
          child: Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.isLost ? Icons.search : Icons.volunteer_activism_outlined,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.isLost ? 'LOST' : 'FOUND',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: statusColor, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    if (item.categoryName != null) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(item.categoryName!),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                    if (isRecentlyPosted(item.createdAt)) ...[
                      const SizedBox(width: 8),
                      const NewBadge(dense: true),
                    ],
                    const Spacer(),
                    if (item.status != 'open')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.status[0].toUpperCase() + item.status.substring(1),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(item.title, style: theme.textTheme.headlineSmall),
                if (item.posterName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Posted by ${item.posterName}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(item.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (item.locationLabel != null)
                        _DetailRow(icon: Icons.location_on_outlined, text: item.locationLabel!),
                      if (item.eventTime != null)
                        _DetailRow(
                          icon: item.isLost ? Icons.search : Icons.pin_drop_outlined,
                          text: '${item.isLost ? 'Lost' : 'Found'} '
                              '${DateFormat.yMMMd().add_jm().format(item.eventTime!)}',
                        ),
                      _DetailRow(
                        icon: Icons.schedule,
                        text: 'Reported ${DateFormat.yMMMd().add_jm().format(item.createdAt)}',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                if (item.locationLabel != null) ...[
                  const SizedBox(height: 16),
                  _LocationPreview(itemId: item.id),
                ],
                const SizedBox(height: 16),
                _PossibleMatchesSection(item: item),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Entry point into [ItemMatchesScreen] for this specific post — a tappable
/// row rather than a whole card, so it reads as "one more thing about this
/// post" alongside the detail rows above it, not as a competing section.
///
/// Shown for the post's own owner unconditionally (checking is always
/// useful, even at zero matches — the destination screen explains why).
/// For anyone else, shown only once this post is already matched against
/// one of *their* own posts — that's the only case where "possible
/// matches" means anything from a non-owner's point of view; otherwise the
/// bottom contact bar is the relevant action, not this.
class _PossibleMatchesSection extends ConsumerWidget {
  const _PossibleMatchesSection({required this.item});

  final ItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    if (myId == null) return const SizedBox.shrink();
    // A returned post is finished — matching no longer applies to it.
    if (item.status == 'resolved') return const SizedBox.shrink();

    final isOwner = item.userId == myId;
    final matchesAsync = ref.watch(matchesProvider);

    return matchesAsync.when(
      // A brief loading flash isn't worth showing its own spinner for —
      // the section just appears a moment after the rest of the page.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (matches) {
        final relevant =
            matches.where((m) => m.myItemId == item.id || m.matchedItemId == item.id).toList();
        if (!isOwner && relevant.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final subtitle = relevant.isEmpty
            ? (isOwner ? 'None yet — the AI checks automatically' : null)
            : '${relevant.length} possible match${relevant.length == 1 ? '' : 'es'}'
                '${isOwner ? '' : ' with one of your posts'}';

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/item/${item.id}/matches', extra: item.title),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('View possible matches', style: theme.textTheme.titleSmall),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
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
  const _DetailRow({required this.icon, required this.text, this.isLast = false});

  final IconData icon;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
