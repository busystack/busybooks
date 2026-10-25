import 'package:flutter_test/flutter_test.dart';
import '../../tools/cache_probe.dart' as probe;

void main() {
  test(
    'EPUB cache probe preserves valid resources and verifies reuse and rejection',
    () async {
      final result = await probe.runCacheProbe();
      expect(result['status'], 'passed');
      expect(result['resources'], 4);
      expect(result['checks'], greaterThanOrEqualTo(19));
    },
  );
}
