// ignore_for_file: text_direction_code_point_in_literal, text_direction_code_point_in_comment

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'BusyBooks';

  @override
  String get reader => 'Lesen';

  @override
  String get allBooks => 'Alle Bücher';

  @override
  String get unread => 'Ungelesen';

  @override
  String get reading => 'Wird gelesen';

  @override
  String get finished => 'Beendet';

  @override
  String get searchBook => 'Im Buch suchen';

  @override
  String get annotations => 'Markierungen und Notizen';

  @override
  String get appearance => 'Darstellung';

  @override
  String get bookmark => 'Lesezeichen';

  @override
  String get highlight => 'Hervorheben';

  @override
  String get dictionary => 'Wörterbuch';

  @override
  String get readAloud => 'Vorlesen';

  @override
  String get nextPage => 'Nächste Seite';

  @override
  String get previousPage => 'Vorherige Seite';

  @override
  String get back => 'Zurück';

  @override
  String get forward => 'Vorwärts';

  @override
  String get fullScreen => 'Vollbild';

  @override
  String get settings => 'Einstellungen';

  @override
  String get commandPalette => 'Befehle';

  @override
  String get exportAnnotations => 'Notizen exportieren';

  @override
  String get exportOriginal => 'Originalbuch exportieren';

  @override
  String get backup => 'Lesedaten sichern';

  @override
  String get restore => 'Sicherung wiederherstellen';

  @override
  String get properties => 'Bucheigenschaften';

  @override
  String get delete => 'Löschen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get close => 'Schließen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get resetAll => 'Alles zurücksetzen';

  @override
  String get title => 'Titel';

  @override
  String get author => 'Autor';

  @override
  String get series => 'Reihe';

  @override
  String get seriesOrder => 'Position in der Reihe';

  @override
  String get language => 'Sprache';

  @override
  String get format => 'Format';

  @override
  String get progress => 'Fortschritt';

  @override
  String get recentlyRead => 'Zuletzt gelesen';

  @override
  String get recentlyAdded => 'Zuletzt hinzugefügt';

  @override
  String get grid => 'Coveransicht';

  @override
  String get list => 'Kompakte Liste';

  @override
  String get sort => 'Sortieren';

  @override
  String get general => 'Allgemein';

  @override
  String get theme => 'Darstellung der Anwendung';

  @override
  String get system => 'Systemsprache';

  @override
  String get light => 'Hell';

  @override
  String get dark => 'Dunkel';

  @override
  String get sepia => 'Sepia';

  @override
  String get appLanguage => 'Sprache der Anwendung';

  @override
  String get keyboardShortcuts => 'Tastaturkürzel';

  @override
  String get pressShortcut => 'Tastenkürzel drücken';

  @override
  String get shortcutConflict =>
      'Dieses Tastenkürzel ist bereits belegt. Wählen Sie ein anderes oder setzen Sie den betreffenden Befehl zurück.';

  @override
  String get shortcutInvalid =>
      'Verwenden Sie eine Kombination mit einer Zusatztaste oder eine Funktionstaste. Tasten für Texteingabe, Navigation und Schließen sind reserviert.';

  @override
  String get shortcutChanged =>
      'Die Tastenkürzel wurden inzwischen geändert. Versuchen Sie es erneut.';

  @override
  String get disabled => 'Deaktiviert';

  @override
  String get publisher => 'Verlagsdarstellung';

  @override
  String get fontFamily => 'Schriftfamilie';

  @override
  String get fontSize => 'Schriftgröße';

  @override
  String get fontWeight => 'Schriftstärke';

  @override
  String get lineSpacing => 'Zeilenabstand';

  @override
  String get paragraphSpacing => 'Absatzabstand';

  @override
  String get margins => 'Seitenränder';

  @override
  String get readingWidth => 'Textbreite';

  @override
  String get alignment => 'Ausrichtung';

  @override
  String get start => 'Anfang';

  @override
  String get justify => 'Blocksatz';

  @override
  String get center => 'Zentriert';

  @override
  String get hyphenation => 'Silbentrennung';

  @override
  String get pageColor => 'Seitenfarbe';

  @override
  String get readingMode => 'Lesemodus';

  @override
  String get paginated => 'Seitenweise';

  @override
  String get continuous => 'Fortlaufend';

  @override
  String get twoPages => 'Doppelseite';

  @override
  String get saveDefaults => 'Als Lesevorgaben speichern';

  @override
  String get resetBook => 'Buchdarstellung zurücksetzen';

  @override
  String get goTo => 'Lesestelle aufrufen';

  @override
  String get location => 'Lesestelle';

  @override
  String get page => 'Seite';

  @override
  String get chapter => 'Kapitel';

  @override
  String get printPage => 'Druckseite';

  @override
  String get generatedPages =>
      'Bildschirmseiten ändern sich mit dem Layout. Sie sind von den Druckseitenangaben des Verlags unabhängig.';

  @override
  String get zoom => 'Zoom';

  @override
  String get fitPage => 'Ganze Seite';

  @override
  String get fitWidth => 'Seitenbreite';

  @override
  String get rotation => 'Drehung';

  @override
  String get thumbnails => 'Seitenvorschaubilder';

  @override
  String get noText =>
      'Diese PDF-Seite enthält keine Textebene. Lesen und Seitenlesezeichen sind möglich. Textauswahl und Wörterbuch benötigen Text auf dieser Seite; die Suche kann weiterhin Text auf anderen Seiten finden.';

  @override
  String get noTextPageStatus => 'Keine Textebene auf dieser Seite';

  @override
  String get searching => 'Suche läuft';

  @override
  String get note => 'Notiz';

  @override
  String get editNote => 'Notiz bearbeiten';

  @override
  String get yellow => 'Gelb';

  @override
  String get green => 'Grün';

  @override
  String get blue => 'Blau';

  @override
  String get pink => 'Rosa';

  @override
  String get selectText =>
      'Wählen Sie im Buch Text aus, um ihn hervorzuheben, zu kopieren oder nachzuschlagen.';

  @override
  String get noAnnotations => 'Noch keine Markierungen oder Notizen';

  @override
  String get play => 'Wiedergabe';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get stop => 'Anhalten';

  @override
  String get voice => 'Stimme';

  @override
  String get speed => 'Geschwindigkeit';

  @override
  String get dictionarySource =>
      'Nachschlagen sendet nur das ausgewählte Wort oder die Wortgruppe über das Internet an das englische Wiktionary und zeigt eine Definition im Lesebereich. „Vollständigen Eintrag öffnen“ öffnet die Quelle im Browser.';

  @override
  String get lookup => 'Nachschlagen';

  @override
  String get externalLink => 'Externen Link öffnen';

  @override
  String get externalWarning =>
      'Diesen Link im Standardbrowser öffnen? Sie verlassen damit das Offline-Lesefenster.';

  @override
  String get open => 'Öffnen';

  @override
  String get backupHelp =>
      'Sicherung und Wiederherstellung von Lesedaten umfasst Sammlungen, Lesepositionen, Anmerkungen, private Notizen und Einstellungen. Originalbuchdateien sind ausgeschlossen.';

  @override
  String get restoreWarning =>
      'Lesedaten in diesem Profil wiederherstellen? Übereinstimmende Buch-, Anmerkungs-, Sammlungs- und Verlaufseinträge werden ersetzt. Andere Daten bleiben erhalten. Originalbuchdateien sind ausgeschlossen und werden nicht verändert.';

  @override
  String get backupComplete => 'Sicherung gespeichert';

  @override
  String get restoreComplete => 'Sicherung wiederhergestellt';

  @override
  String get exportComplete => 'Export gespeichert';

  @override
  String get writeFailed =>
      'Der Vorgang konnte nicht gespeichert werden. Vorhandene Lesedaten und Dateien bleiben erhalten.';

  @override
  String get error => 'Fehler';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get busy => 'Wird bearbeitet';

  @override
  String get chooseCover => 'Cover auswählen';

  @override
  String get removeCover => 'Cover entfernen';

  @override
  String get about => 'Über BusyBooks';

  @override
  String get aboutText =>
      'Eine persönliche Offline-Bibliothek für EPUB, PDF, FB2 und Comics mit Lesefunktion. Auf Basis der BusyStack-Desktop-Grundlage.';

  @override
  String get accessibility => 'Barrierefreiheit';

  @override
  String get reducedMotion =>
      'Systemvorgabe für reduzierte Animationen beachten';

  @override
  String get speechUnavailable =>
      'Vorlesen konnte nicht gestartet werden. Prüfen Sie den installierten Sprachdienst und die Stimmen.';

  @override
  String get windowMinimize => 'Minimieren';

  @override
  String get windowMaximize => 'Maximieren';

  @override
  String get windowRestore => 'Wiederherstellen';

  @override
  String get windowClose => 'Schließen';

  @override
  String get mainMenu => 'Hauptmenü';

  @override
  String get unknownAuthor => 'Unbekannter Autor';

  @override
  String get bookDetails => 'Buchdetails';

  @override
  String get appDataError =>
      'Die Einstellungen konnten nicht geladen werden. Die ursprüngliche Einstellungsdatei bleibt erhalten.';

  @override
  String get countBooks => 'Bücher';

  @override
  String get ready => 'Bereit';

  @override
  String get loadingBook => 'Buch wird geöffnet';

  @override
  String get unsupported =>
      'Unterstützt werden DRM-freie EPUB 2/3, PDF, FB2 (.fb2, .fb2.zip, .fbz), CBZ und CBR.';

  @override
  String get source => 'Quelle';

  @override
  String get noSpeechText =>
      'Die aktuelle Textstelle enthält keinen lesbaren Text.';

  @override
  String get bookError =>
      'Dieses Buch konnte nicht geöffnet werden. Originaldatei und Lesedaten bleiben erhalten.';

  @override
  String get fixedAppearanceHelp =>
      'PDF und EPUB mit festem Layout behalten die veröffentlichte Typografie und Seitengestaltung bei. Einpassen, Zoom, Seitenfarbe und Doppelseiten sind verfügbar.';

  @override
  String get invalidCover =>
      'Wählen Sie ein unterstütztes Bild mit höchstens 4 MiB und 16 Millionen Pixeln.';

  @override
  String get startupFailed => 'Lesedaten konnten nicht geöffnet werden';

  @override
  String get startupRecovery =>
      'Ihre vorhandenen Dateien bleiben erhalten. Prüfen Sie Berechtigungen oder schließen Sie eine andere BusyBooks-Instanz und versuchen Sie es erneut. Starten Sie zur Wiederherstellung beschädigter Lesedaten mit einem leeren BUSYBOOKS_PROFILE und stellen Sie eine Lesedatensicherung in den Einstellungen wieder her.';

  @override
  String get welcome => 'Start';

  @override
  String get workspace => 'Arbeitsbereich';

  @override
  String get openBook => 'Buch öffnen';

  @override
  String get openBookHelp =>
      'EPUB, PDF, FB2, CBZ oder CBR direkt am vorhandenen Speicherort lesen.';

  @override
  String get createCollection => 'Sammlung erstellen';

  @override
  String get createCollectionHelp =>
      'Eine benannte Sammlung in BusyBooks erstellen. Bücher bleiben an ihren ursprünglichen Speicherorten.';

  @override
  String get openCollection => 'Sammlung öffnen';

  @override
  String get openCollectionHelp =>
      'Eine gespeicherte Sammlung in BusyBooks auswählen.';

  @override
  String get addExistingBooks => 'Bücher hinzufügen';

  @override
  String get closeWorkspace => 'Arbeitsbereich schließen';

  @override
  String get refreshWorkspace => 'Arbeitsbereich aktualisieren';

  @override
  String get collection => 'Sammlung';

  @override
  String get book => 'Buch';

  @override
  String get recent => 'Zuletzt geöffnet';

  @override
  String get noRecent =>
      'Zuletzt geöffnete Bücher und Sammlungen erscheinen hier.';

  @override
  String get removeRecent => 'Aus „Zuletzt geöffnet“ entfernen';

  @override
  String get searchCollection => 'Titel, Autor oder Reihe suchen';

  @override
  String get emptyCollection =>
      'Diese Sammlung enthält keine Bücher. Unterstützte Buchdateien von beliebigen Speicherorten hinzufügen.';

  @override
  String get removeReference => 'Aus Sammlung entfernen';

  @override
  String get removeReferenceHelp =>
      'Diese Zuordnung entfernen? Buchdatei und Lesedaten bleiben erhalten.';

  @override
  String get locateBook => 'Buch suchen';

  @override
  String get locateBookHelp =>
      'Buch am gespeicherten Ort nicht gefunden. Es wurde möglicherweise verschoben oder gelöscht oder befindet sich auf einem nicht verfügbaren Laufwerk. Das passende Original suchen, um es neu zuzuordnen. Gespeicherte Notizbuchdaten bleiben verfügbar.';

  @override
  String get fileUnavailable => 'Datei nicht verfügbar';

  @override
  String get fileChanged => 'Buchinhalt geändert';

  @override
  String get fileChangedHelp =>
      'Vorhandene Positionen und Anmerkungen gehören zu anderem Inhalt und bleiben erhalten. Suchen Sie das Original oder öffnen Sie das geänderte Buch mit eigenen Lesedaten.';

  @override
  String get openChangedBook => 'Geändertes Buch öffnen';

  @override
  String get sidebar => 'Seitenleiste';

  @override
  String get books => 'Bücher';

  @override
  String get searchFailed => 'Suche fehlgeschlagen. Erneut versuchen.';

  @override
  String get previousResult => 'Vorheriges Ergebnis';

  @override
  String get nextResult => 'Nächstes Ergebnis';

  @override
  String get readingBack => 'Im Leseverlauf zurück';

  @override
  String get readingForward => 'Im Leseverlauf vorwärts';

  @override
  String get returnToPassage => 'Zur vorherigen Textstelle';

  @override
  String get addNote => 'Notiz hinzufügen';

  @override
  String get removeBookmark => 'Lesezeichen entfernen';

  @override
  String get highlightColor => 'Markierungsfarbe';

  @override
  String get regionColor => 'Bereichsfarbe';

  @override
  String get moreTypography => 'Weitere Typografie';

  @override
  String get regular => 'Normal';

  @override
  String get lightWeight => 'Leicht';

  @override
  String get mediumWeight => 'Mittel';

  @override
  String get semibold => 'Halbfett';

  @override
  String get boldWeight => 'Fett';

  @override
  String get serifFont => 'Serifenschrift';

  @override
  String get sansFont => 'Serifenlos';

  @override
  String get monoFont => 'Nichtproportional';

  @override
  String get pageNumber => 'Seitennummer';

  @override
  String get pageLabel => 'Gedruckte Seitenbezeichnung';

  @override
  String get pageNumberHelp =>
      'Die physische Seitennummer verwenden, beginnend mit 1.';

  @override
  String get invalidPage =>
      'Physische Seite im gültigen Bereich oder genaue Druckseitenbezeichnung eingeben. Für numerische Bezeichnungen = voranstellen.';

  @override
  String get bookProgress => 'Buchfortschritt (%)';

  @override
  String get invalidProgress => 'Einen Prozentwert von 0 bis 100 eingeben.';

  @override
  String get moreActions => 'Weitere Aktionen';

  @override
  String get viewOptions => 'Ansichtsoptionen';

  @override
  String get playback => 'Vorlesesteuerung';

  @override
  String get speechOptions => 'Stimme und Geschwindigkeit';

  @override
  String get annotation => 'Anmerkung';

  @override
  String get go => 'Öffnen';

  @override
  String get emptySearchCollection =>
      'Keine Bücher entsprechen diesen Filtern.';

  @override
  String get collectionSearchScope => 'Sammlung durchsuchen';

  @override
  String get physicalPage => 'Physische Seite';

  @override
  String get pdfDefaults => 'PDF-Standardeinstellungen';

  @override
  String get footnote => 'Fußnote';

  @override
  String get copyShort => 'Kopieren';

  @override
  String get readerStartupTimedOut =>
      'Der Reader wurde nicht gestartet. Schließen und öffnen Sie das Buch erneut. Prüfen Sie bei wiederholtem Auftreten das Anwendungsprotokoll auf einen Reader-Fehler.';

  @override
  String get noCollections =>
      'Noch keine Sammlungen. Auf der Startseite eine erstellen.';

  @override
  String get renameCollection => 'Sammlung umbenennen';

  @override
  String get deleteCollection => 'Sammlung löschen';

  @override
  String get deleteCollectionHelp =>
      'Diese Sammlung und ihre Zuordnungen löschen? Bücher und Lesedaten bleiben erhalten.';

  @override
  String get notebook => 'Notizbuch';

  @override
  String get viewMode => 'Ansicht';

  @override
  String get highlights => 'Markierungen';

  @override
  String get bookmarks => 'Lesezeichen';

  @override
  String get withNotes => 'Mit Notizen';

  @override
  String get searchNotebook => 'Im Notizbuch suchen';

  @override
  String get missingBookNotebook =>
      'Das Originalbuch ist nicht verfügbar. Gespeicherte Passagen und Notizen bleiben bearbeitbar. Das passende Original suchen, um eine Passage zu öffnen.';

  @override
  String get section => 'Abschnitt';

  @override
  String get savedLocation => 'Gespeicherte Textstelle';

  @override
  String get savedPassage => 'Zitat aus dem Buch';

  @override
  String get privateNote => 'Private Notiz';

  @override
  String get unsavedNote => 'Ungespeicherte Notiz';

  @override
  String get noteInputLimit =>
      'Diese Änderung wurde nicht übernommen. Notizen unterstützen bis zu 1.000.000 Texteinheiten und dürfen kein Nullzeichen enthalten. Der bisherige Text bleibt erhalten.';

  @override
  String get noteDeliveryRejected =>
      'Ihr Text befindet sich noch in diesem Editor. Erneut speichern oder mit Schließen in den gemeinsamen Entwurf übertragen. Schlägt die Übertragung fehl, bleibt der Editor geöffnet.';

  @override
  String get noteItemUnavailable =>
      'Dieser gespeicherte Eintrag wurde entfernt. Schließen Sie den Editor; Speichern kann ihn nicht wiederherstellen.';

  @override
  String get savingNote => 'Notiz wird gespeichert…';

  @override
  String get noteSaveStillPending =>
      'Das Speichern läuft noch. Ihr Text bleibt erhalten; BusyBooks wartet auf die Bestätigung.';

  @override
  String get noteSaveFailed =>
      'Die Notiz konnte nicht gespeichert werden. Ihr Entwurf bleibt erhalten.';

  @override
  String get discard => 'Verwerfen';

  @override
  String get discardNoteHelp =>
      'Ungespeicherte Änderungen dieser Notiz verwerfen?';

  @override
  String get showInReading => 'In Leseansicht zeigen';

  @override
  String get removeAnnotationHelp =>
      'Diesen gespeicherten Eintrag und seine private Notiz löschen?';

  @override
  String get moveBook => 'Buch verschieben';

  @override
  String get moveBookHelp =>
      'Nur die ausgewählte Originaldatei an dieses Ziel verschieben. Andere bekannte Kopien bleiben erhalten.';

  @override
  String get moveComplete => 'Buch verschoben und geprüft.';

  @override
  String get pendingMove => 'Buchverschiebung muss wiederhergestellt werden';

  @override
  String get locationUpdated => 'Buchspeicherort aktualisiert und geprüft.';

  @override
  String get unsupportedTarget =>
      'Ordner und Sammlungsdateien werden nicht unterstützt. Eine unterstützte Buchdatei öffnen oder eine in BusyBooks gespeicherte Sammlung auswählen.';

  @override
  String get saveWarning =>
      'Lesedaten konnten nicht gespeichert werden. Das Buch bleibt geöffnet; vor dem Schließen erneut speichern.';

  @override
  String get initializingReader => 'Leseansicht wird initialisiert';

  @override
  String get openingPassage => 'Erste Passage wird geöffnet';

  @override
  String get purple => 'Violett';

  @override
  String get backupAndRestore => 'Lesedaten sichern und wiederherstellen';

  @override
  String get keepFiles => 'Dateien behalten';

  @override
  String get moveRecoveryHelp =>
      'Erneut versuchen, um das Verschieben abzuschließen, oder vorhandene Originale behalten und die Wiederherstellung beenden. BusyBooks entfernt nur die eigene temporäre Kopie, wenn ein geprüftes Original verfügbar ist.';

  @override
  String get moveUnchanged =>
      'Am ausgewählten Speicherort befindet sich bereits diese Buchdatei. Keine Datei wurde verschoben.';

  @override
  String get checkingBook => 'Buchverfügbarkeit wird geprüft';

  @override
  String get restorePreferencesPending =>
      'Lesedaten wurden wiederhergestellt. Einstellungen konnten nicht angewendet werden; dies wird beim nächsten Start erneut versucht.';

  @override
  String get backToCollection => 'Zurück zur Sammlung';

  @override
  String get readerControlsFailed =>
      'Die Lesesteuerung konnte nicht angezeigt werden. Erneut versuchen.';

  @override
  String get navigationInterrupted =>
      'Die Navigation wurde unterbrochen. Erneut versuchen.';

  @override
  String get outline => 'Gliederung';

  @override
  String get noOutline => 'Diese Publikation enthält keine Gliederung.';

  @override
  String get sidebarViewMenu => 'Seitenleistenansicht';

  @override
  String get outlineGroupLocation => 'Abschnittsgruppe ohne Navigationsziel.';

  @override
  String get noPublisherPage =>
      'Für diese Stelle ist keine Seitenangabe des Verlags verfügbar.';

  @override
  String get expandSection => 'Abschnitt aufklappen';

  @override
  String get collapseSection => 'Abschnitt zuklappen';

  @override
  String outlineLevel(int level) {
    return 'Ebene $level';
  }

  @override
  String get thumbnailFailed =>
      'Die Seitenvorschau konnte nicht geladen werden.';

  @override
  String get loadingOutline => 'Gliederung wird geladen…';

  @override
  String get outlineFailed =>
      'Die Gliederung der Publikation konnte nicht geladen werden.';

  @override
  String get thumbnailUnavailable =>
      'Solange das Buch nicht gelesen werden kann, sind keine Seitenvorschauen verfügbar.';

  @override
  String get menuOpenFailed =>
      'Das Menü konnte nicht geöffnet werden. Versuchen Sie es erneut.';

  @override
  String get navigation => 'Navigation';

  @override
  String get annotationActions => 'Anmerkungsaktionen';

  @override
  String get searchThisBook => 'In diesem Buch suchen';

  @override
  String get lookUp => 'Nachschlagen';

  @override
  String get openFullEntry => 'Vollständigen Eintrag öffnen';

  @override
  String get lookupSource => 'Englisches Wiktionary · Online';

  @override
  String get lookupLoading => 'Die vollständige Auswahl wird nachgeschlagen…';

  @override
  String get lookupMissing =>
      'Kein Wiktionary-Eintrag entspricht dieser vollständigen Auswahl. Versuchen Sie eine Wörterbuchform oder eine gebräuchliche Wortgruppe.';

  @override
  String get lookupOffline =>
      'Wiktionary konnte nicht erreicht werden. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut.';

  @override
  String get lookupTimeout =>
      'Wiktionary hat nicht rechtzeitig geantwortet. Versuchen Sie es erneut.';

  @override
  String get lookupUnavailable =>
      'Wiktionary ist nicht verfügbar. Versuchen Sie es später erneut.';

  @override
  String get lookupInvalid =>
      'Wiktionary hat eine nicht unterstützte oder ungültige Antwort geliefert. Versuchen Sie es erneut oder öffnen Sie, falls verfügbar, den vollständigen Eintrag.';

  @override
  String get lookupUnsupported =>
      'Diese Auswahl oder dieser Eintrag kann nicht als kurze Definition angezeigt werden. Wählen Sie ein Wort oder eine kurze Wortgruppe (bis zu 256 Zeichen) oder öffnen Sie, falls verfügbar, den vollständigen Eintrag.';

  @override
  String get lookupExcerpt =>
      'Auszug mit bis zu zwei Bedeutungen pro Abschnitt. Sprachangaben beschreiben die Begriffe und können vom Buch abweichen. Definitionen sind auf Englisch. Der vollständige Eintrag enthält alle Sprachen und Bedeutungen.';

  @override
  String get reflowableDefaults => 'Standard für anpassbaren Lesetext';

  @override
  String get searchFonts => 'Schriften suchen';

  @override
  String get installedFonts => 'Installierte Schriftfamilien';

  @override
  String get installedFont => 'Installierte Schrift';

  @override
  String get genericFontCategory => 'Allgemeine Kategorie';

  @override
  String get currentFont => 'Aktuelle Auswahl';

  @override
  String get loadingFonts => 'Schriften werden geladen…';

  @override
  String get refreshFonts => 'Aktualisieren';

  @override
  String get noMatchingFonts =>
      'Keine passenden Schriften. Versuchen Sie einen anderen Namen.';

  @override
  String get fontCatalogueFailed =>
      'Installierte Schriften konnten nicht geladen werden. Allgemeine Kategorien bleiben verfügbar.';

  @override
  String get fontPreview => 'Schriftvorschau';

  @override
  String get fontPreviewFailed =>
      'Diese Schrift konnte nicht angezeigt werden.';

  @override
  String get fontUnavailable =>
      'Diese Schrift ist nicht verfügbar; die Standardschrift wird verwendet.';

  @override
  String get publisherFontActive =>
      'Die Verlagsdarstellung ist aktiv. Ihre eigene Schrift bleibt gespeichert.';

  @override
  String get fontPublisherHelp =>
      'Eine Schriftauswahl deaktiviert die Verlagsdarstellung. Das Durchsehen ändert nichts.';

  @override
  String get fontApplyFailed =>
      'Die Schrift konnte nicht angewendet werden. Sie können es erneut versuchen.';

  @override
  String get fontSampleProse => 'Ein Buch, 0123456789.';

  @override
  String get fontSampleBold => 'Fette Betonung.';

  @override
  String get fontSampleItalic => 'Eine kursive Stimme.';

  @override
  String get noInstalledFonts =>
      'In dieser Umgebung sind keine installierten Schriftfamilien verfügbar.';

  @override
  String get rememberedFont => 'Gespeicherte Schrift';

  @override
  String get regionNote => 'Bereichsnotiz';

  @override
  String get regionNotes => 'Bereichsnotizen';

  @override
  String get comicDefaults => 'Comic-Lesevorgaben';

  @override
  String get readingDirection => 'Leserichtung';

  @override
  String get directionAuto => 'Aus dem Buch';

  @override
  String get directionLtr => 'Von links nach rechts';

  @override
  String get directionRtl => 'Von rechts nach links';

  @override
  String get regionInstructions =>
      'Ein Rechteck auf einer Seite auswählen. Pfeiltasten verschieben es; Umschalt+Pfeil ändert die Größe; Eingabe bestätigt; Escape bricht ab.';

  @override
  String get protectedBookHelp =>
      'Geschützte Bücher und verschlüsselte Archive können nicht geöffnet werden. Lesedaten bleiben erhalten.';

  @override
  String get bookResourceLimitHelp =>
      'Dieses Buch überschreitet eine Ressourcengrenze. Die Details nennen die betroffene Datei oder Ressource.';

  @override
  String get damagedBookHelp =>
      'Das Buch ist beschädigt oder hat ungültige Inhalte. Eine vollständige, lesbare Kopie desselben Originals suchen, um seine Lesedaten zu behalten.';

  @override
  String get firstPage => 'Erste Seite';

  @override
  String get lastPage => 'Letzte Seite';

  @override
  String get home => 'Startseite';

  @override
  String get marks => 'Markierungen';

  @override
  String get bookText => 'Buchtext';

  @override
  String get chapters => 'Kapitel';

  @override
  String get searchCategory => 'Suchkategorie';

  @override
  String get closeSearch => 'Suche schließen';

  @override
  String get searchNeedsReading =>
      'Öffnen Sie die Leseansicht, um das Buch zu durchsuchen oder Seitenvorschauen zu laden.';

  @override
  String get enterSearch => 'Text für die Suche eingeben.';

  @override
  String get noResults => 'Keine Ergebnisse';

  @override
  String get allTypes => 'Alle Typen';

  @override
  String get bookOrder => 'Buchreihenfolge';

  @override
  String get type => 'Typ';

  @override
  String get noNotebookResults => 'Keine Einträge entsprechen diesen Filtern.';

  @override
  String get clearFilters => 'Filter zurücksetzen';

  @override
  String get saved => 'Gespeichert';

  @override
  String get showFullNote => 'Vollständige Notiz anzeigen';

  @override
  String get showLess => 'Weniger anzeigen';

  @override
  String get bookActions => 'Buchaktionen';

  @override
  String get aboutBusyBooks => 'Über BusyBooks';

  @override
  String get data => 'Daten';

  @override
  String get systemControlled => 'Vom System gesteuert';

  @override
  String get motionReduced => 'Reduziert';

  @override
  String get motionEnabled => 'Animationen aktiviert';

  @override
  String get moreReadingSettings => 'Weitere Leseeinstellungen…';

  @override
  String get pageDestination => 'Seitenzahl oder gedruckte Seitenbezeichnung';

  @override
  String get pageDestinationHelp =>
      'Zahlen wählen physische Seiten. Verwenden Sie =Bezeichnung für gedruckte Seitenbezeichnungen.';

  @override
  String bareBookmarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Lesezeichen ohne Notizen',
      one: '1 Lesezeichen ohne Notiz',
    );
    return '$_temp0';
  }

  @override
  String get search => 'Suche';

  @override
  String get actions => 'Aktionen';

  @override
  String get sortBy => 'Sortieren nach';

  @override
  String get readingDefaults => 'Lesevorgaben';

  @override
  String get closeCollection => 'Sammlung schließen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get anyNotes => 'Notiz optional';

  @override
  String get dateUnavailable => 'Datum nicht verfügbar';

  @override
  String get regionPreviewUnavailable =>
      'Bereichsvorschau nicht verfügbar. Die private Notiz bleibt zugänglich.';

  @override
  String get regionPreviewLoading => 'Bereichsvorschau wird geladen';

  @override
  String get searchBooks => 'Bücher durchsuchen';

  @override
  String get searchRecent => 'Zuletzt geöffnet durchsuchen';

  @override
  String get searchBookmarks => 'Lesezeichen durchsuchen';

  @override
  String get searchChapters => 'Kapitel durchsuchen';

  @override
  String get searchBookText => 'Buchtext durchsuchen';

  @override
  String get thisBook => 'Dieses Buch';

  @override
  String get currentCollection => 'Aktuelle Sammlung';

  @override
  String get allSavedBooks => 'Alle gespeicherten Bücher';

  @override
  String get searchScope => 'Suchbereich';

  @override
  String get showMoreResults => 'Weitere Ergebnisse anzeigen';

  @override
  String get searchUnavailable => 'Suchquelle ist nicht verfügbar';

  @override
  String get searchIncomplete => 'Ergebnisse sind unvollständig';

  @override
  String get searchDisabled => 'In diesem Kontext nicht verfügbar';

  @override
  String get searchContext => 'Suche:';

  @override
  String searchLoadedResults(int count) {
    return '$count Ergebnisse angezeigt';
  }

  @override
  String get searchMoreAvailable => 'Weitere Ergebnisse sind verfügbar.';

  @override
  String get searchEarlierResults =>
      'Frühere Ergebnisse liegen außerhalb dieses Bereichs. Erneut suchen, um zum Anfang zurückzukehren.';

  @override
  String get split => 'Geteilte Ansicht';

  @override
  String get resizeSplitPanes => 'Bereiche für Lesen und Notizbuch anpassen';

  @override
  String splitPaneRatio(int reading, int notebook) {
    return 'Lesen $reading %, Notizbuch $notebook %';
  }

  @override
  String get resizeSplitPanesHelp =>
      'Mit Pfeil nach links und rechts die Bereiche anpassen.';

  @override
  String splitMinimumWidth(int width) {
    return 'Benötigt $width px Inhaltsbreite.';
  }

  @override
  String splitCollapsed(String pane) {
    return 'Die geteilte Ansicht zeigt wegen des begrenzten Platzes vorübergehend $pane.';
  }

  @override
  String showSplitPane(String pane) {
    return '$pane anzeigen';
  }

  @override
  String get menuUnavailable =>
      'Das Menü konnte nicht geöffnet werden. Bitte erneut versuchen.';
}
