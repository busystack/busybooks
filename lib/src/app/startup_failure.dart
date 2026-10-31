import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../l10n/generated/app_localizations.dart';
import 'app_locale.dart';
import 'app_theme.dart';
import 'busybooks_design.dart';
import 'busybooks_toast.dart';
import 'desktop_frame.dart';
import 'localization.dart';
import 'system_accent.dart';

// A failed profile open must leave the user's data intact and explain recovery.
class BusyBooksStartupFailure extends StatelessWidget {
  const BusyBooksStartupFailure({
    super.key,
    required this.error,
    required this.retry,
  });
  final Object error;
  final Future<void> Function() retry;

  @override
  Widget build(BuildContext context) => ProviderScope(
    child: MaterialApp(
      title: 'BusyBooks',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveBusyBooksLocales,
      theme: buildBusyBooksTheme(
        brightness: Brightness.light,
        accentColor: busyBooksDefaultAccentColor,
      ),
      darkTheme: buildBusyBooksTheme(
        brightness: Brightness.dark,
        accentColor: busyBooksDefaultAccentColor,
      ),
      home: BusyBooksToastOverlay(
        child: Builder(
          builder: (context) => desktopWindowHost(
            Material(
              child: Center(
                child: BusyBooksDialogShell(
                  title: context.l10n.startupFailed,
                  actions: [
                    BusyBooksDialogButton(
                      label: context.l10n.close,
                      onPressed: () => windowManager.close(),
                    ),
                    BusyBooksDialogButton(
                      label: context.l10n.retry,
                      suggested: true,
                      onPressed: retry,
                    ),
                  ],
                  children: [
                    Text(context.l10n.startupRecovery),
                    const SizedBox(height: BusyBooksSpacing.md),
                    SelectableText(
                      contextMenuBuilder: busyBooksTextContextMenu,
                      error.toString(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
