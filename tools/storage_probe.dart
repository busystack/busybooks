import 'dart:convert';
import 'dart:io';
import '../test/support/file_workspace_scenario.dart';
import '../test/support/backup_contract_scenario.dart';

Future<void> main(List<String> args) async {
  stdout.writeln(
    jsonEncode(
      args.contains('--backup-contract')
          ? await runBackupContractScenario()
          : await runFileWorkspaceScenario(),
    ),
  );
}
