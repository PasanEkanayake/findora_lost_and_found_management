/// The label shown to other people next to a post's location.
///
/// Deliberately coarse: a neighbourhood or town, never a street or house
/// number. (It used to be "street, town", which gave the exact address away
/// even though the map pin is approximate — see
/// supabase/33_approximate_locations.sql, which also strips the street
/// server-side from anything an older app sends.)
///
/// Takes the pieces of a reverse-geocoded address and picks the most local
/// one that isn't a street: the sub-locality (neighbourhood) if there is one,
/// else the locality (town / city), else the administrative area, else
/// "Pinned location". Always a single part, with no comma.
String publicLocationLabel({
  String? subLocality,
  String? locality,
  String? administrativeArea,
}) {
  for (final part in [subLocality, locality, administrativeArea]) {
    final cleaned = part?.replaceAll(',', ' ').trim();
    if (cleaned != null && cleaned.isNotEmpty) return cleaned;
  }
  return 'Pinned location';
}
