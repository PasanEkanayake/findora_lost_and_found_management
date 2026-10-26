/// Radius of the circle drawn around a post's approximate public location.
///
/// The server snaps a pinned point to the centre of a grid cell about 550 m
/// across (`public_location_grid_degrees()` in
/// supabase/33_approximate_locations.sql), so the real spot is never more
/// than about 400 m from the centre; the circle covers that. Keep the two in
/// step if the grid size is changed.
const double approximateAreaRadiusMeters = 400;
