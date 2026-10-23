import 'package:flutter_test/flutter_test.dart';
import '../support/backup_contract_scenario.dart';

void main() {
  test(
    'backup writer and restore share combined-record and encoded-byte boundaries',
    () async {
      final result = await runBackupContractScenario();
      expect(result['status'], 'passed');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
