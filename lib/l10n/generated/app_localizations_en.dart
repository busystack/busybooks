// ignore_for_file: text_direction_code_point_in_literal, text_direction_code_point_in_comment

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BusyBooks';

  @override
  String get reader => 'Reader';

  @override
  String get allBooks => 'All Books';

  @override
  String get unread => 'Unread';

  @override
  String get reading => 'Reading';

  @override
  String get finished => 'Finished';

  @override
  String get searchBook => 'Search in Book';

  @override
  String get annotations => 'Annotations';

  @override
  String get appearance => 'Appearance';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get highlight => 'Highlight';

  @override
  String get dictionary => 'Dictionary';

  @override
  String get readAloud => 'Read Aloud';

  @override
  String get nextPage => 'Next Page';

  @override
  String get previousPage => 'Previous Page';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get fullScreen => 'Full Screen';

  @override
  String get settings => 'Settings';

  @override
  String get commandPalette => 'Commands';

  @override
  String get exportAnnotations => 'Export Annotations';

  @override
  String get exportOriginal => 'Export Original Book';

  @override
  String get backup => 'Back Up Reading Data';

  @override
  String get restore => 'Restore Backup';

  @override
  String get properties => 'Book Properties';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get reset => 'Reset';

  @override
  String get resetAll => 'Reset All';

  @override
  String get title => 'Title';

  @override
  String get author => 'Author';

  @override
  String get series => 'Series';

  @override
  String get seriesOrder => 'Series order';

  @override
  String get language => 'Language';

  @override
  String get format => 'Format';

  @override
  String get progress => 'Progress';

  @override
  String get recentlyRead => 'Recently read';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get grid => 'Cover grid';

  @override
  String get list => 'Compact list';

  @override
  String get sort => 'Sort';

  @override
  String get general => 'General';

  @override
  String get theme => 'Application appearance';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get sepia => 'Sepia';

  @override
  String get appLanguage => 'Application language';

  @override
  String get keyboardShortcuts => 'Keyboard Shortcuts';

  @override
  String get pressShortcut => 'Press a shortcut';

  @override
  String get shortcutConflict =>
      'This shortcut is already assigned. Choose another shortcut or reset the conflicting command.';

  @override
  String get shortcutInvalid =>
      'Use a modifier with a key, or a function key. Text editing, traversal and dismissal keys are reserved.';

  @override
  String get shortcutChanged => 'The shortcut settings changed. Try again.';

  @override
  String get disabled => 'Disabled';

  @override
  String get publisher => 'Publisher appearance';

  @override
  String get fontFamily => 'Font family';

  @override
  String get fontSize => 'Font size';

  @override
  String get fontWeight => 'Font weight';

  @override
  String get lineSpacing => 'Line spacing';

  @override
  String get paragraphSpacing => 'Paragraph spacing';

  @override
  String get margins => 'Margins';

  @override
  String get readingWidth => 'Reading width';

  @override
  String get alignment => 'Alignment';

  @override
  String get start => 'Start';

  @override
  String get justify => 'Justified';

  @override
  String get center => 'Centered';

  @override
  String get hyphenation => 'Hyphenation';

  @override
  String get pageColor => 'Page color';

  @override
  String get readingMode => 'Reading mode';

  @override
  String get paginated => 'Paginated';

  @override
  String get continuous => 'Continuous';

  @override
  String get twoPages => 'Two-page spread';

  @override
  String get saveDefaults => 'Save as Reading Defaults';

  @override
  String get resetBook => 'Reset Book Appearance';

  @override
  String get goTo => 'Go to Location';

  @override
  String get location => 'Location';

  @override
  String get page => 'Page';

  @override
  String get chapter => 'Chapter';

  @override
  String get printPage => 'Print page';

  @override
  String get generatedPages =>
      'Screen pages change with layout. They are separate from publisher print-page references.';

  @override
  String get zoom => 'Zoom';

  @override
  String get fitPage => 'Fit page';

  @override
  String get fitWidth => 'Fit width';

  @override
  String get rotation => 'Rotation';

  @override
  String get thumbnails => 'Thumbnails';

  @override
  String get noText =>
      'This PDF page has no text layer. Reading and page bookmarks are available. Text selection and dictionary need text on this page; search can still find text on other pages.';

  @override
  String get noTextPageStatus => 'No text layer on this page';

  @override
  String get searching => 'Searching';

  @override
  String get note => 'Note';

  @override
  String get editNote => 'Edit Note';

  @override
  String get yellow => 'Yellow';

  @override
  String get green => 'Green';

  @override
  String get blue => 'Blue';

  @override
  String get pink => 'Pink';

  @override
  String get selectText =>
      'Select text in the book to highlight, copy or look up a word.';

  @override
  String get noAnnotations => 'No annotations yet';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get stop => 'Stop';

  @override
  String get voice => 'Voice';

  @override
  String get speed => 'Speed';

  @override
  String get dictionarySource =>
      'Look Up sends only the selected word or phrase to English Wiktionary over the internet and shows a definition inside the reader. Open Full Entry opens the source in your browser.';

  @override
  String get lookup => 'Look Up';

  @override
  String get externalLink => 'Open External Link';

  @override
  String get externalWarning =>
      'Open this link in your default browser? This leaves the offline reader.';

  @override
  String get open => 'Open';

  @override
  String get backupHelp =>
      'Backup & Restore Reading Data includes collections, reading positions, annotations, private notes and preferences. Original book files are excluded.';

  @override
  String get restoreWarning =>
      'Restore reading data into this profile? Matching book, annotation, collection and Recent records will be replaced. Unrelated data is kept. Original book files are excluded and will not be changed.';

  @override
  String get backupComplete => 'Backup saved';

  @override
  String get restoreComplete => 'Backup restored';

  @override
  String get exportComplete => 'Export saved';

  @override
  String get writeFailed =>
      'The operation could not be saved. Your existing reading data and files have been retained.';

  @override
  String get error => 'Error';

  @override
  String get retry => 'Retry';

  @override
  String get busy => 'Working';

  @override
  String get chooseCover => 'Choose Cover';

  @override
  String get removeCover => 'Remove Cover';

  @override
  String get about => 'About BusyBooks';

  @override
  String get aboutText =>
      'An offline personal EPUB, PDF, FB2 and comic library and reader. Built with the BusyStack desktop foundation.';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get reducedMotion => 'Follow system reduced motion';

  @override
  String get speechUnavailable =>
      'Read-aloud could not start. Check the installed speech service and language voices.';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowRestore => 'Restore';

  @override
  String get windowClose => 'Close';

  @override
  String get mainMenu => 'Main Menu';

  @override
  String get unknownAuthor => 'Unknown author';

  @override
  String get bookDetails => 'Book details';

  @override
  String get appDataError =>
      'Settings could not be loaded. The original settings file has been preserved.';

  @override
  String get countBooks => 'Books';

  @override
  String get ready => 'Ready';

  @override
  String get loadingBook => 'Opening book';

  @override
  String get unsupported =>
      'Only DRM-free EPUB 2/3, PDF, FB2 (.fb2, .fb2.zip, .fbz), CBZ and CBR are supported.';

  @override
  String get source => 'Source';

  @override
  String get noSpeechText =>
      'There is no readable text in the current passage.';

  @override
  String get bookError =>
      'This book could not be opened. The original file and your reading data are preserved.';

  @override
  String get fixedAppearanceHelp =>
      'PDF and fixed-layout EPUB retain their published typography and composition. Fit, zoom, page color and spreads are available.';

  @override
  String get invalidCover =>
      'Choose a supported image up to 4 MiB and 16 million pixels.';

  @override
  String get startupFailed => 'Reading data could not be opened';

  @override
  String get startupRecovery =>
      'Your existing files have been preserved. Check permissions or close another BusyBooks instance, then retry. To recover damaged reading data, start with an empty BUSYBOOKS_PROFILE and restore a reading-data backup in Settings.';

  @override
  String get welcome => 'Home';

  @override
  String get workspace => 'Workspace';

  @override
  String get openBook => 'Open Book';

  @override
  String get openBookHelp =>
      'Read an EPUB, PDF, FB2, CBZ or CBR from its current location.';

  @override
  String get createCollection => 'Create Collection';

  @override
  String get createCollectionHelp =>
      'Create a named collection in BusyBooks. Books remain at their original locations.';

  @override
  String get openCollection => 'Open Collection';

  @override
  String get openCollectionHelp => 'Choose a saved collection from BusyBooks.';

  @override
  String get addExistingBooks => 'Add Books';

  @override
  String get closeWorkspace => 'Close Workspace';

  @override
  String get refreshWorkspace => 'Refresh Workspace';

  @override
  String get collection => 'Collection';

  @override
  String get book => 'Book';

  @override
  String get recent => 'Recent';

  @override
  String get noRecent =>
      'Recently opened books and collections will appear here.';

  @override
  String get removeRecent => 'Remove from Recent';

  @override
  String get searchCollection => 'Search title, author or series';

  @override
  String get emptyCollection =>
      'This collection has no books. Add supported book files from any location.';

  @override
  String get removeReference => 'Remove from Collection';

  @override
  String get removeReferenceHelp =>
      'Remove this membership? The book file and reading data are kept.';

  @override
  String get locateBook => 'Locate Book';

  @override
  String get locateBookHelp =>
      'Book not found at its saved location. It may have been moved, deleted, or be on an unavailable drive. Locate the matching original to reconnect it. Saved Notebook data remains available.';

  @override
  String get fileUnavailable => 'File unavailable';

  @override
  String get fileChanged => 'Book contents changed';

  @override
  String get fileChangedHelp =>
      'Existing positions and annotations belong to different content and have been preserved. Locate the original or open the changed book with separate reading data.';

  @override
  String get openChangedBook => 'Open Changed Book';

  @override
  String get sidebar => 'Sidebar';

  @override
  String get books => 'Books';

  @override
  String get searchFailed => 'Search failed. Try again.';

  @override
  String get previousResult => 'Previous Result';

  @override
  String get nextResult => 'Next Result';

  @override
  String get readingBack => 'Reading History Back';

  @override
  String get readingForward => 'Reading History Forward';

  @override
  String get returnToPassage => 'Return to Previous Passage';

  @override
  String get addNote => 'Add Note';

  @override
  String get removeBookmark => 'Remove Bookmark';

  @override
  String get highlightColor => 'Highlight Color';

  @override
  String get regionColor => 'Region Color';

  @override
  String get moreTypography => 'More Typography';

  @override
  String get regular => 'Regular';

  @override
  String get lightWeight => 'Light';

  @override
  String get mediumWeight => 'Medium';

  @override
  String get semibold => 'Semibold';

  @override
  String get boldWeight => 'Bold';

  @override
  String get serifFont => 'Serif';

  @override
  String get sansFont => 'Sans Serif';

  @override
  String get monoFont => 'Monospace';

  @override
  String get pageNumber => 'Page number';

  @override
  String get pageLabel => 'Printed page label';

  @override
  String get pageNumberHelp => 'Use the physical page number, starting at 1.';

  @override
  String get invalidPage =>
      'Enter a physical page in range or an exact printed label. Use = for a numeric label.';

  @override
  String get bookProgress => 'Book progress (%)';

  @override
  String get invalidProgress => 'Enter a percentage from 0 to 100.';

  @override
  String get moreActions => 'More Actions';

  @override
  String get viewOptions => 'View Options';

  @override
  String get playback => 'Read-Aloud Playback';

  @override
  String get speechOptions => 'Voice and Speed';

  @override
  String get annotation => 'Annotation';

  @override
  String get go => 'Go';

  @override
  String get emptySearchCollection => 'No books match these filters.';

  @override
  String get collectionSearchScope => 'Search Collection';

  @override
  String get physicalPage => 'Physical page';

  @override
  String get pdfDefaults => 'PDF Defaults';

  @override
  String get footnote => 'Footnote';

  @override
  String get copyShort => 'Copy';

  @override
  String get readerStartupTimedOut =>
      'The reader did not start. Close and reopen the book. If this continues, check the application log for a reader error.';

  @override
  String get noCollections => 'No collections yet. Create one from Home.';

  @override
  String get renameCollection => 'Rename Collection';

  @override
  String get deleteCollection => 'Delete Collection';

  @override
  String get deleteCollectionHelp =>
      'Delete this collection and its memberships? Books and reading data are kept.';

  @override
  String get notebook => 'Notebook';

  @override
  String get viewMode => 'View';

  @override
  String get highlights => 'Highlights';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get withNotes => 'With Notes';

  @override
  String get searchNotebook => 'Search in Notebook';

  @override
  String get missingBookNotebook =>
      'The original book is unavailable. Your saved passages and notes remain editable. Locate the matching original to jump to a passage.';

  @override
  String get section => 'Section';

  @override
  String get savedLocation => 'Saved passage location';

  @override
  String get savedPassage => 'Quotation from the book';

  @override
  String get privateNote => 'Private Note';

  @override
  String get unsavedNote => 'Unsaved note';

  @override
  String get noteInputLimit =>
      'This change was not accepted. Notes support up to 1,000,000 text units and cannot contain a null character. Your previous text is unchanged.';

  @override
  String get noteDeliveryRejected =>
      'Your text is still in this editor. Retry Save, or Close to transfer it to the shared draft. If transfer fails, the editor stays open.';

  @override
  String get noteItemUnavailable =>
      'This saved item was removed. Close this editor; saving cannot recreate it.';

  @override
  String get savingNote => 'Saving note…';

  @override
  String get noteSaveStillPending =>
      'Saving is still pending. Your text is protected; waiting for confirmation.';

  @override
  String get noteSaveFailed =>
      'Note could not be saved. Your draft is retained.';

  @override
  String get discard => 'Discard';

  @override
  String get discardNoteHelp => 'Discard the unsaved changes to this note?';

  @override
  String get showInReading => 'Show in Reading';

  @override
  String get removeAnnotationHelp =>
      'Delete this saved item and its private note?';

  @override
  String get moveBook => 'Move Book';

  @override
  String get moveBookHelp =>
      'Move only the selected original file to this destination. Other known copies are kept.';

  @override
  String get moveComplete => 'Book moved and verified.';

  @override
  String get pendingMove => 'Move Book needs recovery';

  @override
  String get locationUpdated => 'Book location updated and verified.';

  @override
  String get unsupportedTarget =>
      'Folders and collection files are unsupported. Open a supported book file or choose a collection saved in BusyBooks.';

  @override
  String get saveWarning =>
      'Reading data could not be saved. The book remains open; retry saving before closing.';

  @override
  String get initializingReader => 'Initializing Reader';

  @override
  String get openingPassage => 'Opening First Passage';

  @override
  String get purple => 'Purple';

  @override
  String get backupAndRestore => 'Backup & Restore Reading Data';

  @override
  String get keepFiles => 'Keep Files';

  @override
  String get moveRecoveryHelp =>
      'Retry to complete this move, or keep existing originals and stop recovery. BusyBooks removes only its own temporary copy when a verified original is available.';

  @override
  String get moveUnchanged =>
      'The selected location already contains this physical book. No file was moved.';

  @override
  String get checkingBook => 'Checking book availability';

  @override
  String get restorePreferencesPending =>
      'Reading data was restored. Preferences could not be applied; they will be retried at the next start.';

  @override
  String get backToCollection => 'Back to Collection';

  @override
  String get readerControlsFailed =>
      'Reader controls could not be displayed. Try again.';

  @override
  String get navigationInterrupted => 'Navigation was interrupted. Try again.';

  @override
  String get outline => 'Outline';

  @override
  String get noOutline => 'No outline supplied by this publication.';

  @override
  String get sidebarViewMenu => 'Sidebar View';

  @override
  String get outlineGroupLocation =>
      'Section group without a navigation destination.';

  @override
  String get noPublisherPage =>
      'No publisher page reference is available for this location.';

  @override
  String get expandSection => 'Expand section';

  @override
  String get collapseSection => 'Collapse section';

  @override
  String outlineLevel(int level) {
    return 'Level $level';
  }

  @override
  String get thumbnailFailed => 'Page preview could not be loaded.';

  @override
  String get loadingOutline => 'Loading outline…';

  @override
  String get outlineFailed => 'The publication outline could not be loaded.';

  @override
  String get thumbnailUnavailable =>
      'Page previews are unavailable while the book cannot be read.';

  @override
  String get menuOpenFailed => 'Could not open the menu. Try again.';

  @override
  String get navigation => 'Navigation';

  @override
  String get annotationActions => 'Annotation Actions';

  @override
  String get searchThisBook => 'Search in This Book';

  @override
  String get lookUp => 'Look Up';

  @override
  String get openFullEntry => 'Open Full Entry';

  @override
  String get lookupSource => 'English Wiktionary · Online';

  @override
  String get lookupLoading => 'Looking up the complete selection…';

  @override
  String get lookupMissing =>
      'No Wiktionary entry matches this complete selection. Try a dictionary form or an established phrase.';

  @override
  String get lookupOffline =>
      'Could not connect to Wiktionary. Check your connection and retry.';

  @override
  String get lookupTimeout => 'Wiktionary took too long to respond. Try again.';

  @override
  String get lookupUnavailable => 'Wiktionary is unavailable. Try again later.';

  @override
  String get lookupInvalid =>
      'Wiktionary returned an unsupported or invalid response. Try again or open the full entry when available.';

  @override
  String get lookupUnsupported =>
      'This selection or entry cannot be shown as a short definition. Select a word or short phrase (up to 256 characters), or open the full entry when available.';

  @override
  String get lookupExcerpt =>
      'Excerpt with up to two senses per section. Language labels describe the terms; they may differ from the book. Definitions are in English. Open the full entry for all languages and senses.';

  @override
  String get reflowableDefaults => 'Reflowable Reading Defaults';

  @override
  String get searchFonts => 'Search fonts';

  @override
  String get installedFonts => 'Installed families';

  @override
  String get installedFont => 'Installed font';

  @override
  String get genericFontCategory => 'Generic category';

  @override
  String get currentFont => 'Current selection';

  @override
  String get loadingFonts => 'Loading fonts…';

  @override
  String get refreshFonts => 'Refresh';

  @override
  String get noMatchingFonts => 'No matching fonts. Try another name.';

  @override
  String get fontCatalogueFailed =>
      'Installed fonts could not be loaded. Generic choices are still available.';

  @override
  String get fontPreview => 'Font preview';

  @override
  String get fontPreviewFailed => 'This font could not be previewed.';

  @override
  String get fontUnavailable =>
      'This font is unavailable; using the default font.';

  @override
  String get publisherFontActive =>
      'Publisher appearance is active. Your custom font is remembered.';

  @override
  String get fontPublisherHelp =>
      'Choosing a font turns off publisher appearance. Browsing leaves it unchanged.';

  @override
  String get fontApplyFailed =>
      'The font could not be applied. Your choice can be retried.';

  @override
  String get fontSampleProse => 'A book, 0123456789.';

  @override
  String get fontSampleBold => 'Bold emphasis.';

  @override
  String get fontSampleItalic => 'An italic voice.';

  @override
  String get noInstalledFonts =>
      'No installed families are available in this environment.';

  @override
  String get rememberedFont => 'Saved font';

  @override
  String get regionNote => 'Region note';

  @override
  String get regionNotes => 'Region notes';

  @override
  String get comicDefaults => 'Comic Reading Defaults';

  @override
  String get readingDirection => 'Reading direction';

  @override
  String get directionAuto => 'From book';

  @override
  String get directionLtr => 'Left to right';

  @override
  String get directionRtl => 'Right to left';

  @override
  String get regionInstructions =>
      'Select a rectangle on one page. Arrow keys move it; Shift+Arrow resizes; Enter confirms; Escape cancels.';

  @override
  String get protectedBookHelp =>
      'Protected books and encrypted archives cannot be opened. Reading data is preserved.';

  @override
  String get bookResourceLimitHelp =>
      'This book exceeds a reading resource limit. Details below identify the affected file or resource.';

  @override
  String get damagedBookHelp =>
      'The book is damaged or has invalid content. Locate a complete, readable copy of the same original to keep its reading data.';

  @override
  String get firstPage => 'First page';

  @override
  String get lastPage => 'Last page';

  @override
  String get home => 'Home';

  @override
  String get marks => 'Marks';

  @override
  String get bookText => 'Book Text';

  @override
  String get chapters => 'Chapters';

  @override
  String get searchCategory => 'Search category';

  @override
  String get closeSearch => 'Close Search';

  @override
  String get searchNeedsReading =>
      'Open Reading to search the publication or load page previews.';

  @override
  String get enterSearch => 'Enter text to search.';

  @override
  String get noResults => 'No results';

  @override
  String get allTypes => 'All types';

  @override
  String get bookOrder => 'Book Order';

  @override
  String get type => 'Type';

  @override
  String get noNotebookResults => 'No items match these filters.';

  @override
  String get clearFilters => 'Clear Filters';

  @override
  String get saved => 'Saved';

  @override
  String get showFullNote => 'Show Full Note';

  @override
  String get showLess => 'Show Less';

  @override
  String get bookActions => 'Book Actions';

  @override
  String get aboutBusyBooks => 'About BusyBooks';

  @override
  String get data => 'Data';

  @override
  String get systemControlled => 'Controlled by your system';

  @override
  String get motionReduced => 'Reduced';

  @override
  String get motionEnabled => 'Animations enabled';

  @override
  String get moreReadingSettings => 'More Reading Settings…';

  @override
  String get pageDestination => 'Page number or printed label';

  @override
  String get pageDestinationHelp =>
      'Numbers select physical pages. Use =label for a printed label.';

  @override
  String bareBookmarks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookmarks without notes',
      one: '1 bookmark without notes',
    );
    return '$_temp0';
  }

  @override
  String get search => 'Search';

  @override
  String get actions => 'Actions';

  @override
  String get sortBy => 'Sort by';

  @override
  String get readingDefaults => 'Reading defaults';

  @override
  String get closeCollection => 'Close Collection';

  @override
  String get refresh => 'Refresh';

  @override
  String get anyNotes => 'Any notes';

  @override
  String get dateUnavailable => 'Date unavailable';

  @override
  String get regionPreviewUnavailable =>
      'Region preview unavailable. The private note is still accessible.';

  @override
  String get regionPreviewLoading => 'Loading region preview';

  @override
  String get searchBooks => 'Search Books';

  @override
  String get searchRecent => 'Search Recent';

  @override
  String get searchBookmarks => 'Search Bookmarks';

  @override
  String get searchChapters => 'Search Chapters';

  @override
  String get searchBookText => 'Search Book Text';

  @override
  String get thisBook => 'This Book';

  @override
  String get currentCollection => 'Current Collection';

  @override
  String get allSavedBooks => 'All Saved Books';

  @override
  String get searchScope => 'Search scope';

  @override
  String get showMoreResults => 'Show more results';

  @override
  String get searchUnavailable => 'Search source is unavailable';

  @override
  String get searchIncomplete => 'Results are incomplete';

  @override
  String get searchDisabled => 'Unavailable in this context';

  @override
  String get searchContext => 'Search:';

  @override
  String searchLoadedResults(int count) {
    return '$count results shown';
  }

  @override
  String get searchMoreAvailable => 'More results are available.';

  @override
  String get searchEarlierResults =>
      'Earlier results are outside this window. Search again to return to the beginning.';

  @override
  String get split => 'Split';

  @override
  String get resizeSplitPanes => 'Resize Reading and Notebook panes';

  @override
  String splitPaneRatio(int reading, int notebook) {
    return 'Reading $reading%, Notebook $notebook%';
  }

  @override
  String get resizeSplitPanesHelp =>
      'Use Left and Right arrow keys to resize panes.';

  @override
  String splitMinimumWidth(int width) {
    return 'Needs $width px of content width.';
  }

  @override
  String splitCollapsed(String pane) {
    return 'Split temporarily shows $pane while space is limited.';
  }

  @override
  String showSplitPane(String pane) {
    return 'Show $pane';
  }

  @override
  String get menuUnavailable =>
      'The menu could not be opened. Please try again.';
}
