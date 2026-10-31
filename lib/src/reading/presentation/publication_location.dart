import '../../../l10n/generated/app_localizations.dart';
import '../domain/publication_outline.dart';

String describePublicationPage(
  AppLocalizations l,
  PublicationPageReference reference, {
  bool grouping = false,
}) {
  if (reference.physicalPage != null) {
    final physical =
        '${l.physicalPage} ${reference.physicalPage}${reference.totalPages == null ? '' : ' / ${reference.totalPages}'}';
    return '${l.page} ${reference.display} · $physical';
  }
  if (reference.label != null) return '${l.printPage} ${reference.label}';
  return grouping ? l.outlineGroupLocation : l.noPublisherPage;
}
