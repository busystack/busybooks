// Adapted from BusyMark's About dialog and informational identity (Apache-2.0).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_metadata.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_glyphs.dart';
import 'localization.dart';
import 'product_actions.dart';

const _websiteUrl = 'https://busystack.org';
const _repositoryUrl = 'https://github.com/busystack/busybooks/';
const _licenseUrl = 'https://www.apache.org/licenses/LICENSE-2.0';

Future<void> showBusyBooksAboutDialog(BuildContext context) =>
    showBusyBooksModalDialog<void>(
      context,
      builder: (_) => const _BusyBooksAboutDialog(),
    );

class _BusyBooksAboutDialog extends StatelessWidget {
  const _BusyBooksAboutDialog();

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final l = context.l10n;
    Widget link(String title, String subtitle, IconData icon, String url) =>
        BusyBooksActionRow(
          title: title,
          subtitle: subtitle,
          leading: Icon(icon),
          trailing: const Icon(BusyBooksGlyphs.externalLink),
          onTap: () => unawaited(
            runAppAction(context, () async {
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
            }),
          ),
        );
    return BusyBooksDialogShell(
      title: l.aboutBusyBooks,
      maxWidth: 420,
      header: BusyBooksDialogTitleBar(closeSemanticLabel: l.close),
      children: [
        BusyBooksDialogIdentity(
          title: l.appTitle,
          visual: Semantics(
            image: true,
            label: l.appTitle,
            child: ExcludeSemantics(
              child: Image.asset(
                'assets/branding/busybooks_logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: BusyBooksSpacing.xs),
        Text(
          l.aboutTagline,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
        ),
        const SizedBox(height: BusyBooksSpacing.sm),
        const _AboutVersionTag(version: busyBooksAppVersion),
        const SizedBox(height: BusyBooksSpacing.md),
        BusyBooksGroupedList(
          filled: true,
          children: [
            link(
              l.aboutLicenseLabel,
              l.aboutLicenseName,
              BusyBooksGlyphs.info,
              _licenseUrl,
            ),
            link(
              l.aboutWebsite,
              _websiteUrl,
              BusyBooksGlyphs.home,
              _websiteUrl,
            ),
            link(
              l.aboutSourceCode,
              _repositoryUrl,
              BusyBooksGlyphs.code,
              _repositoryUrl,
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutVersionTag extends StatelessWidget {
  const _AboutVersionTag({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: DecoratedBox(
        key: const ValueKey('about-version-tag'),
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(BusyBooksRadius.pill),
          border: Border.all(color: colorScheme.primary),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BusyBooksSpacing.md,
            vertical: BusyBooksSpacing.xs,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              version,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
