import 'package:flutter_test/flutter_test.dart';

import 'support/flows.dart';

void main() {
  testWidgets('offline banner: appears, says Back online, and keeps screen state',
      (tester) async {
    await offlineBannerFlow(tester);
  });
}
