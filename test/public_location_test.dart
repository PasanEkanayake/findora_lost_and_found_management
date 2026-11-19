import 'package:findora/core/location/approximate_area.dart';
import 'package:findora/core/location/public_location_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('publicLocationLabel', () {
    test('prefers the neighbourhood and never includes a street', () {
      expect(
        publicLocationLabel(subLocality: 'Orchard', locality: 'Singapore'),
        'Orchard',
      );
    });

    test('falls back to the town, then the region', () {
      expect(publicLocationLabel(locality: 'Singapore'), 'Singapore');
      expect(publicLocationLabel(subLocality: '', locality: ' ', administrativeArea: 'Selangor'),
          'Selangor');
    });

    test('nothing usable: a neutral label', () {
      expect(publicLocationLabel(), 'Pinned location');
    });

    test('is always a single part — no comma for the server to cut at', () {
      expect(publicLocationLabel(subLocality: 'Marina, Bay', locality: 'Singapore'),
          isNot(contains(',')));
    });
  });

  group('approximateAreaRadiusMeters', () {
    test('covers the farthest a point can be from its grid-cell centre', () {
      // Cells are ~555 m on a side (0.005 degrees of latitude), so the corner
      // is sqrt(2) * 277.5 m = ~392 m from the centre.
      expect(approximateAreaRadiusMeters, greaterThanOrEqualTo(392));
    });
  });
}
