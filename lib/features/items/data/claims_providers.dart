import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'claim_model.dart';
import 'claims_repository.dart';

final claimsRepositoryProvider = Provider<ClaimsRepository>((ref) {
  return const ClaimsRepository();
});

/// Everything ChatScreen's status banner needs about the claim → approve
/// → mark-returned → rate lifecycle for one conversation, fetched
/// together so the banner doesn't flicker through several loading states.
class ChatLifecycleStatus {
  const ChatLifecycleStatus({
    required this.claim,
    required this.itemStatus,
    required this.iHaveRated,
  });

  final ClaimModel? claim;
  final String itemStatus; // 'open' | 'matched' | 'claimed' | 'resolved'
  final bool iHaveRated;
}

class ChatLifecycleParams {
  const ChatLifecycleParams({
    required this.foundItemId,
    required this.claimantId,
    required this.myId,
  });

  /// Claims are always filed against the item with type 'found' — you
  /// claim something someone found, proving you're the one who lost it.
  final String foundItemId;
  final String claimantId;
  final String myId;

  @override
  bool operator ==(Object other) =>
      other is ChatLifecycleParams &&
      other.foundItemId == foundItemId &&
      other.claimantId == claimantId &&
      other.myId == myId;

  @override
  int get hashCode => Object.hash(foundItemId, claimantId, myId);
}

final chatLifecycleProvider = FutureProvider.autoDispose
    .family<ChatLifecycleStatus, ChatLifecycleParams>((ref, params) async {
  final repo = ref.watch(claimsRepositoryProvider);
  final claim = await repo.fetchClaim(itemId: params.foundItemId, claimantId: params.claimantId);
  final status = await repo.fetchItemStatus(params.foundItemId);
  final rated = status == 'resolved'
      ? await repo.hasRated(itemId: params.foundItemId, raterId: params.myId)
      : false;
  return ChatLifecycleStatus(claim: claim, itemStatus: status, iHaveRated: rated);
});
