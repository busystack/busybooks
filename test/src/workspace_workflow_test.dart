import 'package:flutter_test/flutter_test.dart';
import '../support/file_workspace_scenario.dart';

void main() {
  test(
    'original files, independent collections and reading data survive reopen and backup',
    () async {
      final result = await runFileWorkspaceScenario();
      expect(result['status'], 'passed');
      expect(result['checks'], greaterThanOrEqualTo(45));
    },
  );
}
