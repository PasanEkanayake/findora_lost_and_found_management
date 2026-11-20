import 'package:findora/core/router/deep_links.dart';
import 'package:findora/core/sharing/share_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '3f2b8c1e-9a4d-4e57-8b21-6c0d5e7f9a10';

  group('ShareLinks.normaliseBaseUrl', () {
    test('keeps a clean https URL, dropping trailing slashes', () {
      expect(ShareLinks.normaliseBaseUrl('https://share.example.com'), 'https://share.example.com');
      expect(ShareLinks.normaliseBaseUrl(' https://share.example.com/// '), 'https://share.example.com');
      expect(ShareLinks.normaliseBaseUrl('https://example.com/findora/'), 'https://example.com/findora');
    });

    test('blank, missing or not a web URL: not configured', () {
      expect(ShareLinks.normaliseBaseUrl(null), isNull);
      expect(ShareLinks.normaliseBaseUrl('   '), isNull);
      expect(ShareLinks.normaliseBaseUrl('share.example.com'), isNull);
      expect(ShareLinks.normaliseBaseUrl('ftp://share.example.com'), isNull);
      expect(ShareLinks.normaliseBaseUrl('javascript:alert(1)'), isNull);
    });
  });

  group('ShareLinks.postUrl', () {
    test('is <base>/p/<id>', () {
      expect(ShareLinks.postUrl(id, baseUrl: 'https://share.example.com/'),
          'https://share.example.com/p/$id');
    });

    test('without a usable base URL there is no link (so no Share button)', () {
      expect(ShareLinks.postUrl(id, baseUrl: ''), isNull);
    });
  });

  group('ShareLinks.shareText', () {
    test('only the title and the link', () {
      expect(
        ShareLinks.shareText(isLost: true, title: 'Black wallet', url: 'https://x/p/1'),
        'Lost: Black wallet\nSee it on Findora: https://x/p/1',
      );
      expect(
        ShareLinks.shareText(isLost: false, title: 'Umbrella', url: 'https://x/p/2'),
        'Found: Umbrella\nSee it on Findora: https://x/p/2',
      );
    });
  });

  group('itemRouteForSharedPath', () {
    test('the https link path and the findora:// path both open the post page', () {
      expect(itemRouteForSharedPath('/p/$id'), '/item/$id');
      expect(itemRouteForSharedPath('/open/p/$id'), '/item/$id');
    });

    test('ignores a query string and normalises the id to lower case', () {
      expect(itemRouteForSharedPath('/p/${id.toUpperCase()}?utm=whatsapp'), '/item/$id');
    });

    test('anything else is not a shared-post link', () {
      expect(itemRouteForSharedPath('/feed'), isNull);
      expect(itemRouteForSharedPath('/p'), isNull);
      expect(itemRouteForSharedPath('/item/$id'), isNull);
      expect(itemRouteForSharedPath('/p/$id/extra'), isNull);
      expect(itemRouteForSharedPath('/open/$id'), isNull);
    });

    test('a malformed or hostile id never becomes a route', () {
      expect(itemRouteForSharedPath('/p/not-a-uuid'), isNull);
      expect(itemRouteForSharedPath('/p/..%2F..%2Fadmin'), isNull);
      expect(itemRouteForSharedPath('/p/$id%00'), isNull);
      expect(itemRouteForSharedPath('/p/${id}x'), isNull);
    });
  });
}
