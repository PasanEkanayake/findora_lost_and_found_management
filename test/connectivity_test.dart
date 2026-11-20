import 'package:findora/core/connectivity/connectivity_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reachabilityTarget', () {
    test('https URL: host with the default port 443', () {
      final target = reachabilityTarget('https://abcd.supabase.co');
      expect(target?.host, 'abcd.supabase.co');
      expect(target?.port, 443);
    });

    test('an explicit port is kept (e.g. a local Supabase)', () {
      final target = reachabilityTarget('http://192.168.1.5:54321');
      expect(target?.host, '192.168.1.5');
      expect(target?.port, 54321);
    });

    test('surrounding spaces are ignored', () {
      expect(reachabilityTarget('  https://abcd.supabase.co  ')?.host, 'abcd.supabase.co');
    });

    test('missing or malformed URL means nothing to check', () {
      expect(reachabilityTarget(null), isNull);
      expect(reachabilityTarget(''), isNull);
      expect(reachabilityTarget('   '), isNull);
      expect(reachabilityTarget('not a url'), isNull);
    });
  });
}
