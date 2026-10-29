// ignore_for_file: text_direction_code_point_in_literal, text_direction_code_point_in_comment
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'BusyBooks'**
  String get appTitle;

  /// No description provided for @reader.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get reader;

  /// No description provided for @allBooks.
  ///
  /// In en, this message translates to:
  /// **'All Books'**
  String get allBooks;

  /// No description provided for @unread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// No description provided for @finished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get finished;

  /// No description provided for @searchBook.
  ///
  /// In en, this message translates to:
  /// **'Search in Book'**
  String get searchBook;

  /// No description provided for @annotations.
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get annotations;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmark;

  /// No description provided for @highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlight;

  /// No description provided for @dictionary.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get dictionary;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read Aloud'**
  String get readAloud;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get nextPage;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get previousPage;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full Screen'**
  String get fullScreen;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @commandPalette.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commandPalette;

  /// No description provided for @exportAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Export Annotations'**
  String get exportAnnotations;

  /// No description provided for @exportOriginal.
  ///
  /// In en, this message translates to:
  /// **'Export Original Book'**
  String get exportOriginal;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Back Up Reading Data'**
  String get backup;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get restore;

  /// No description provided for @properties.
  ///
  /// In en, this message translates to:
  /// **'Book Properties'**
  String get properties;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @resetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset All'**
  String get resetAll;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @series.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series;

  /// No description provided for @seriesOrder.
  ///
  /// In en, this message translates to:
  /// **'Series order'**
  String get seriesOrder;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progress;

  /// No description provided for @recentlyRead.
  ///
  /// In en, this message translates to:
  /// **'Recently read'**
  String get recentlyRead;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get recentlyAdded;

  /// No description provided for @grid.
  ///
  /// In en, this message translates to:
  /// **'Cover grid'**
  String get grid;

  /// No description provided for @list.
  ///
  /// In en, this message translates to:
  /// **'Compact list'**
  String get list;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Application appearance'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @sepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get sepia;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'Application language'**
  String get appLanguage;

  /// No description provided for @keyboardShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get keyboardShortcuts;

  /// No description provided for @pressShortcut.
  ///
  /// In en, this message translates to:
  /// **'Press a shortcut'**
  String get pressShortcut;

  /// No description provided for @shortcutConflict.
  ///
  /// In en, this message translates to:
  /// **'This shortcut is already assigned. Choose another shortcut or reset the conflicting command.'**
  String get shortcutConflict;

  /// No description provided for @shortcutInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a modifier with a key, or a function key. Text editing, traversal and dismissal keys are reserved.'**
  String get shortcutInvalid;

  /// No description provided for @shortcutChanged.
  ///
  /// In en, this message translates to:
  /// **'The shortcut settings changed. Try again.'**
  String get shortcutChanged;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @publisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher appearance'**
  String get publisher;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font family'**
  String get fontFamily;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @fontWeight.
  ///
  /// In en, this message translates to:
  /// **'Font weight'**
  String get fontWeight;

  /// No description provided for @lineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get lineSpacing;

  /// No description provided for @paragraphSpacing.
  ///
  /// In en, this message translates to:
  /// **'Paragraph spacing'**
  String get paragraphSpacing;

  /// No description provided for @margins.
  ///
  /// In en, this message translates to:
  /// **'Margins'**
  String get margins;

  /// No description provided for @readingWidth.
  ///
  /// In en, this message translates to:
  /// **'Reading width'**
  String get readingWidth;

  /// No description provided for @alignment.
  ///
  /// In en, this message translates to:
  /// **'Alignment'**
  String get alignment;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @justify.
  ///
  /// In en, this message translates to:
  /// **'Justified'**
  String get justify;

  /// No description provided for @center.
  ///
  /// In en, this message translates to:
  /// **'Centered'**
  String get center;

  /// No description provided for @hyphenation.
  ///
  /// In en, this message translates to:
  /// **'Hyphenation'**
  String get hyphenation;

  /// No description provided for @pageColor.
  ///
  /// In en, this message translates to:
  /// **'Page color'**
  String get pageColor;

  /// No description provided for @readingMode.
  ///
  /// In en, this message translates to:
  /// **'Reading mode'**
  String get readingMode;

  /// No description provided for @paginated.
  ///
  /// In en, this message translates to:
  /// **'Paginated'**
  String get paginated;

  /// No description provided for @continuous.
  ///
  /// In en, this message translates to:
  /// **'Continuous'**
  String get continuous;

  /// No description provided for @twoPages.
  ///
  /// In en, this message translates to:
  /// **'Two-page spread'**
  String get twoPages;

  /// No description provided for @saveDefaults.
  ///
  /// In en, this message translates to:
  /// **'Save as Reading Defaults'**
  String get saveDefaults;

  /// No description provided for @resetBook.
  ///
  /// In en, this message translates to:
  /// **'Reset Book Appearance'**
  String get resetBook;

  /// No description provided for @goTo.
  ///
  /// In en, this message translates to:
  /// **'Go to Location'**
  String get goTo;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @chapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get chapter;

  /// No description provided for @printPage.
  ///
  /// In en, this message translates to:
  /// **'Print page'**
  String get printPage;

  /// No description provided for @generatedPages.
  ///
  /// In en, this message translates to:
  /// **'Screen pages change with layout. They are separate from publisher print-page references.'**
  String get generatedPages;

  /// No description provided for @zoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get zoom;

  /// No description provided for @fitPage.
  ///
  /// In en, this message translates to:
  /// **'Fit page'**
  String get fitPage;

  /// No description provided for @fitWidth.
  ///
  /// In en, this message translates to:
  /// **'Fit width'**
  String get fitWidth;

  /// No description provided for @rotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get rotation;

  /// No description provided for @thumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get thumbnails;

  /// No description provided for @noText.
  ///
  /// In en, this message translates to:
  /// **'This PDF page has no text layer. Reading and page bookmarks are available. Text selection and dictionary need text on this page; search can still find text on other pages.'**
  String get noText;

  /// No description provided for @noTextPageStatus.
  ///
  /// In en, this message translates to:
  /// **'No text layer on this page'**
  String get noTextPageStatus;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get searching;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNote;

  /// No description provided for @yellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get yellow;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// No description provided for @selectText.
  ///
  /// In en, this message translates to:
  /// **'Select text in the book to highlight, copy or look up a word.'**
  String get selectText;

  /// No description provided for @noAnnotations.
  ///
  /// In en, this message translates to:
  /// **'No annotations yet'**
  String get noAnnotations;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @dictionarySource.
  ///
  /// In en, this message translates to:
  /// **'Look Up sends only the selected word or phrase to English Wiktionary over the internet and shows a definition inside the reader. Open Full Entry opens the source in your browser.'**
  String get dictionarySource;

  /// No description provided for @lookup.
  ///
  /// In en, this message translates to:
  /// **'Look Up'**
  String get lookup;

  /// No description provided for @externalLink.
  ///
  /// In en, this message translates to:
  /// **'Open External Link'**
  String get externalLink;

  /// No description provided for @externalWarning.
  ///
  /// In en, this message translates to:
  /// **'Open this link in your default browser? This leaves the offline reader.'**
  String get externalWarning;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @backupHelp.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore Reading Data includes collections, reading positions, annotations, private notes and preferences. Original book files are excluded.'**
  String get backupHelp;

  /// No description provided for @restoreWarning.
  ///
  /// In en, this message translates to:
  /// **'Restore reading data into this profile? Matching book, annotation, collection and Recent records will be replaced. Unrelated data is kept. Original book files are excluded and will not be changed.'**
  String get restoreWarning;

  /// No description provided for @backupComplete.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupComplete;

  /// No description provided for @restoreComplete.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get restoreComplete;

  /// No description provided for @exportComplete.
  ///
  /// In en, this message translates to:
  /// **'Export saved'**
  String get exportComplete;

  /// No description provided for @writeFailed.
  ///
  /// In en, this message translates to:
  /// **'The operation could not be saved. Your existing reading data and files have been retained.'**
  String get writeFailed;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @busy.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get busy;

  /// No description provided for @chooseCover.
  ///
  /// In en, this message translates to:
  /// **'Choose Cover'**
  String get chooseCover;

  /// No description provided for @removeCover.
  ///
  /// In en, this message translates to:
  /// **'Remove Cover'**
  String get removeCover;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About BusyBooks'**
  String get about;

  /// No description provided for @aboutText.
  ///
  /// In en, this message translates to:
  /// **'An offline personal EPUB, PDF, FB2 and comic library and reader. Built with the BusyStack desktop foundation.'**
  String get aboutText;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @reducedMotion.
  ///
  /// In en, this message translates to:
  /// **'Follow system reduced motion'**
  String get reducedMotion;

  /// No description provided for @speechUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Read-aloud could not start. Check the installed speech service and language voices.'**
  String get speechUnavailable;

  /// No description provided for @windowMinimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get windowMaximize;

  /// No description provided for @windowRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get windowRestore;

  /// No description provided for @windowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get windowClose;

  /// No description provided for @mainMenu.
  ///
  /// In en, this message translates to:
  /// **'Main Menu'**
  String get mainMenu;

  /// No description provided for @unknownAuthor.
  ///
  /// In en, this message translates to:
  /// **'Unknown author'**
  String get unknownAuthor;

  /// No description provided for @bookDetails.
  ///
  /// In en, this message translates to:
  /// **'Book details'**
  String get bookDetails;

  /// No description provided for @appDataError.
  ///
  /// In en, this message translates to:
  /// **'Settings could not be loaded. The original settings file has been preserved.'**
  String get appDataError;

  /// No description provided for @countBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get countBooks;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @loadingBook.
  ///
  /// In en, this message translates to:
  /// **'Opening book'**
  String get loadingBook;

  /// No description provided for @unsupported.
  ///
  /// In en, this message translates to:
  /// **'Only DRM-free EPUB 2/3, PDF, FB2 (.fb2, .fb2.zip, .fbz), CBZ and CBR are supported.'**
  String get unsupported;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @noSpeechText.
  ///
  /// In en, this message translates to:
  /// **'There is no readable text in the current passage.'**
  String get noSpeechText;

  /// No description provided for @bookError.
  ///
  /// In en, this message translates to:
  /// **'This book could not be opened. The original file and your reading data are preserved.'**
  String get bookError;

  /// No description provided for @fixedAppearanceHelp.
  ///
  /// In en, this message translates to:
  /// **'PDF and fixed-layout EPUB retain their published typography and composition. Fit, zoom, page color and spreads are available.'**
  String get fixedAppearanceHelp;

  /// No description provided for @invalidCover.
  ///
  /// In en, this message translates to:
  /// **'Choose a supported image up to 4 MiB and 16 million pixels.'**
  String get invalidCover;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Reading data could not be opened'**
  String get startupFailed;

  /// No description provided for @startupRecovery.
  ///
  /// In en, this message translates to:
  /// **'Your existing files have been preserved. Check permissions or close another BusyBooks instance, then retry. To recover damaged reading data, start with an empty BUSYBOOKS_PROFILE and restore a reading-data backup in Settings.'**
  String get startupRecovery;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get welcome;

  /// No description provided for @workspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspace;

  /// No description provided for @openBook.
  ///
  /// In en, this message translates to:
  /// **'Open Book'**
  String get openBook;

  /// No description provided for @openBookHelp.
  ///
  /// In en, this message translates to:
  /// **'Read an EPUB, PDF, FB2, CBZ or CBR from its current location.'**
  String get openBookHelp;

  /// No description provided for @createCollection.
  ///
  /// In en, this message translates to:
  /// **'Create Collection'**
  String get createCollection;

  /// No description provided for @createCollectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Create a named collection in BusyBooks. Books remain at their original locations.'**
  String get createCollectionHelp;

  /// No description provided for @openCollection.
  ///
  /// In en, this message translates to:
  /// **'Open Collection'**
  String get openCollection;

  /// No description provided for @openCollectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a saved collection from BusyBooks.'**
  String get openCollectionHelp;

  /// No description provided for @addExistingBooks.
  ///
  /// In en, this message translates to:
  /// **'Add Books'**
  String get addExistingBooks;

  /// No description provided for @closeWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Close Workspace'**
  String get closeWorkspace;

  /// No description provided for @refreshWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Refresh Workspace'**
  String get refreshWorkspace;

  /// No description provided for @collection.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get collection;

  /// No description provided for @book.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get book;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @noRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently opened books and collections will appear here.'**
  String get noRecent;

  /// No description provided for @removeRecent.
  ///
  /// In en, this message translates to:
  /// **'Remove from Recent'**
  String get removeRecent;

  /// No description provided for @searchCollection.
  ///
  /// In en, this message translates to:
  /// **'Search title, author or series'**
  String get searchCollection;

  /// No description provided for @emptyCollection.
  ///
  /// In en, this message translates to:
  /// **'This collection has no books. Add supported book files from any location.'**
  String get emptyCollection;

  /// No description provided for @removeReference.
  ///
  /// In en, this message translates to:
  /// **'Remove from Collection'**
  String get removeReference;

  /// No description provided for @removeReferenceHelp.
  ///
  /// In en, this message translates to:
  /// **'Remove this membership? The book file and reading data are kept.'**
  String get removeReferenceHelp;

  /// No description provided for @locateBook.
  ///
  /// In en, this message translates to:
  /// **'Locate Book'**
  String get locateBook;

  /// No description provided for @locateBookHelp.
  ///
  /// In en, this message translates to:
  /// **'Book not found at its saved location. It may have been moved, deleted, or be on an unavailable drive. Locate the matching original to reconnect it. Saved Notebook data remains available.'**
  String get locateBookHelp;

  /// No description provided for @fileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'File unavailable'**
  String get fileUnavailable;

  /// No description provided for @fileChanged.
  ///
  /// In en, this message translates to:
  /// **'Book contents changed'**
  String get fileChanged;

  /// No description provided for @fileChangedHelp.
  ///
  /// In en, this message translates to:
  /// **'Existing positions and annotations belong to different content and have been preserved. Locate the original or open the changed book with separate reading data.'**
  String get fileChangedHelp;

  /// No description provided for @openChangedBook.
  ///
  /// In en, this message translates to:
  /// **'Open Changed Book'**
  String get openChangedBook;

  /// No description provided for @sidebar.
  ///
  /// In en, this message translates to:
  /// **'Sidebar'**
  String get sidebar;

  /// No description provided for @books.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get books;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed. Try again.'**
  String get searchFailed;

  /// No description provided for @previousResult.
  ///
  /// In en, this message translates to:
  /// **'Previous Result'**
  String get previousResult;

  /// No description provided for @nextResult.
  ///
  /// In en, this message translates to:
  /// **'Next Result'**
  String get nextResult;

  /// No description provided for @readingBack.
  ///
  /// In en, this message translates to:
  /// **'Reading History Back'**
  String get readingBack;

  /// No description provided for @readingForward.
  ///
  /// In en, this message translates to:
  /// **'Reading History Forward'**
  String get readingForward;

  /// No description provided for @returnToPassage.
  ///
  /// In en, this message translates to:
  /// **'Return to Previous Passage'**
  String get returnToPassage;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get addNote;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove Bookmark'**
  String get removeBookmark;

  /// No description provided for @highlightColor.
  ///
  /// In en, this message translates to:
  /// **'Highlight Color'**
  String get highlightColor;

  /// No description provided for @regionColor.
  ///
  /// In en, this message translates to:
  /// **'Region Color'**
  String get regionColor;

  /// No description provided for @moreTypography.
  ///
  /// In en, this message translates to:
  /// **'More Typography'**
  String get moreTypography;

  /// No description provided for @regular.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get regular;

  /// No description provided for @lightWeight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightWeight;

  /// No description provided for @mediumWeight.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get mediumWeight;

  /// No description provided for @semibold.
  ///
  /// In en, this message translates to:
  /// **'Semibold'**
  String get semibold;

  /// No description provided for @boldWeight.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get boldWeight;

  /// No description provided for @serifFont.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get serifFont;

  /// No description provided for @sansFont.
  ///
  /// In en, this message translates to:
  /// **'Sans Serif'**
  String get sansFont;

  /// No description provided for @monoFont.
  ///
  /// In en, this message translates to:
  /// **'Monospace'**
  String get monoFont;

  /// No description provided for @pageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page number'**
  String get pageNumber;

  /// No description provided for @pageLabel.
  ///
  /// In en, this message translates to:
  /// **'Printed page label'**
  String get pageLabel;

  /// No description provided for @pageNumberHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the physical page number, starting at 1.'**
  String get pageNumberHelp;

  /// No description provided for @invalidPage.
  ///
  /// In en, this message translates to:
  /// **'Enter a physical page in range or an exact printed label. Use = for a numeric label.'**
  String get invalidPage;

  /// No description provided for @bookProgress.
  ///
  /// In en, this message translates to:
  /// **'Book progress (%)'**
  String get bookProgress;

  /// No description provided for @invalidProgress.
  ///
  /// In en, this message translates to:
  /// **'Enter a percentage from 0 to 100.'**
  String get invalidProgress;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get moreActions;

  /// No description provided for @viewOptions.
  ///
  /// In en, this message translates to:
  /// **'View Options'**
  String get viewOptions;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Read-Aloud Playback'**
  String get playback;

  /// No description provided for @speechOptions.
  ///
  /// In en, this message translates to:
  /// **'Voice and Speed'**
  String get speechOptions;

  /// No description provided for @annotation.
  ///
  /// In en, this message translates to:
  /// **'Annotation'**
  String get annotation;

  /// No description provided for @go.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get go;

  /// No description provided for @emptySearchCollection.
  ///
  /// In en, this message translates to:
  /// **'No books match these filters.'**
  String get emptySearchCollection;

  /// No description provided for @collectionSearchScope.
  ///
  /// In en, this message translates to:
  /// **'Search Collection'**
  String get collectionSearchScope;

  /// No description provided for @physicalPage.
  ///
  /// In en, this message translates to:
  /// **'Physical page'**
  String get physicalPage;

  /// No description provided for @pdfDefaults.
  ///
  /// In en, this message translates to:
  /// **'PDF Defaults'**
  String get pdfDefaults;

  /// No description provided for @footnote.
  ///
  /// In en, this message translates to:
  /// **'Footnote'**
  String get footnote;

  /// No description provided for @copyShort.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyShort;

  /// No description provided for @readerStartupTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The reader did not start. Close and reopen the book. If this continues, check the application log for a reader error.'**
  String get readerStartupTimedOut;

  /// No description provided for @noCollections.
  ///
  /// In en, this message translates to:
  /// **'No collections yet. Create one from Home.'**
  String get noCollections;

  /// No description provided for @renameCollection.
  ///
  /// In en, this message translates to:
  /// **'Rename Collection'**
  String get renameCollection;

  /// No description provided for @deleteCollection.
  ///
  /// In en, this message translates to:
  /// **'Delete Collection'**
  String get deleteCollection;

  /// No description provided for @deleteCollectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Delete this collection and its memberships? Books and reading data are kept.'**
  String get deleteCollectionHelp;

  /// No description provided for @notebook.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get notebook;

  /// No description provided for @viewMode.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewMode;

  /// No description provided for @highlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlights;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @withNotes.
  ///
  /// In en, this message translates to:
  /// **'With Notes'**
  String get withNotes;

  /// No description provided for @searchNotebook.
  ///
  /// In en, this message translates to:
  /// **'Search in Notebook'**
  String get searchNotebook;

  /// No description provided for @missingBookNotebook.
  ///
  /// In en, this message translates to:
  /// **'The original book is unavailable. Your saved passages and notes remain editable. Locate the matching original to jump to a passage.'**
  String get missingBookNotebook;

  /// No description provided for @section.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get section;

  /// No description provided for @savedLocation.
  ///
  /// In en, this message translates to:
  /// **'Saved passage location'**
  String get savedLocation;

  /// No description provided for @savedPassage.
  ///
  /// In en, this message translates to:
  /// **'Quotation from the book'**
  String get savedPassage;

  /// No description provided for @privateNote.
  ///
  /// In en, this message translates to:
  /// **'Private Note'**
  String get privateNote;

  /// No description provided for @unsavedNote.
  ///
  /// In en, this message translates to:
  /// **'Unsaved note'**
  String get unsavedNote;

  /// No description provided for @noteInputLimit.
  ///
  /// In en, this message translates to:
  /// **'This change was not accepted. Notes support up to 1,000,000 text units and cannot contain a null character. Your previous text is unchanged.'**
  String get noteInputLimit;

  /// No description provided for @noteDeliveryRejected.
  ///
  /// In en, this message translates to:
  /// **'Your text is still in this editor. Retry Save, or Close to transfer it to the shared draft. If transfer fails, the editor stays open.'**
  String get noteDeliveryRejected;

  /// No description provided for @noteItemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This saved item was removed. Close this editor; saving cannot recreate it.'**
  String get noteItemUnavailable;

  /// No description provided for @savingNote.
  ///
  /// In en, this message translates to:
  /// **'Saving note…'**
  String get savingNote;

  /// No description provided for @noteSaveStillPending.
  ///
  /// In en, this message translates to:
  /// **'Saving is still pending. Your text is protected; waiting for confirmation.'**
  String get noteSaveStillPending;

  /// No description provided for @noteSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Note could not be saved. Your draft is retained.'**
  String get noteSaveFailed;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @discardNoteHelp.
  ///
  /// In en, this message translates to:
  /// **'Discard the unsaved changes to this note?'**
  String get discardNoteHelp;

  /// No description provided for @showInReading.
  ///
  /// In en, this message translates to:
  /// **'Show in Reading'**
  String get showInReading;

  /// No description provided for @removeAnnotationHelp.
  ///
  /// In en, this message translates to:
  /// **'Delete this saved item and its private note?'**
  String get removeAnnotationHelp;

  /// No description provided for @moveBook.
  ///
  /// In en, this message translates to:
  /// **'Move Book'**
  String get moveBook;

  /// No description provided for @moveBookHelp.
  ///
  /// In en, this message translates to:
  /// **'Move only the selected original file to this destination. Other known copies are kept.'**
  String get moveBookHelp;

  /// No description provided for @moveComplete.
  ///
  /// In en, this message translates to:
  /// **'Book moved and verified.'**
  String get moveComplete;

  /// No description provided for @pendingMove.
  ///
  /// In en, this message translates to:
  /// **'Move Book needs recovery'**
  String get pendingMove;

  /// No description provided for @locationUpdated.
  ///
  /// In en, this message translates to:
  /// **'Book location updated and verified.'**
  String get locationUpdated;

  /// No description provided for @unsupportedTarget.
  ///
  /// In en, this message translates to:
  /// **'Folders and collection files are unsupported. Open a supported book file or choose a collection saved in BusyBooks.'**
  String get unsupportedTarget;

  /// No description provided for @saveWarning.
  ///
  /// In en, this message translates to:
  /// **'Reading data could not be saved. The book remains open; retry saving before closing.'**
  String get saveWarning;

  /// No description provided for @initializingReader.
  ///
  /// In en, this message translates to:
  /// **'Initializing Reader'**
  String get initializingReader;

  /// No description provided for @openingPassage.
  ///
  /// In en, this message translates to:
  /// **'Opening First Passage'**
  String get openingPassage;

  /// No description provided for @purple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get purple;

  /// No description provided for @backupAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore Reading Data'**
  String get backupAndRestore;

  /// No description provided for @keepFiles.
  ///
  /// In en, this message translates to:
  /// **'Keep Files'**
  String get keepFiles;

  /// No description provided for @moveRecoveryHelp.
  ///
  /// In en, this message translates to:
  /// **'Retry to complete this move, or keep existing originals and stop recovery. BusyBooks removes only its own temporary copy when a verified original is available.'**
  String get moveRecoveryHelp;

  /// No description provided for @moveUnchanged.
  ///
  /// In en, this message translates to:
  /// **'The selected location already contains this physical book. No file was moved.'**
  String get moveUnchanged;

  /// No description provided for @checkingBook.
  ///
  /// In en, this message translates to:
  /// **'Checking book availability'**
  String get checkingBook;

  /// No description provided for @restorePreferencesPending.
  ///
  /// In en, this message translates to:
  /// **'Reading data was restored. Preferences could not be applied; they will be retried at the next start.'**
  String get restorePreferencesPending;

  /// No description provided for @backToCollection.
  ///
  /// In en, this message translates to:
  /// **'Back to Collection'**
  String get backToCollection;

  /// No description provided for @readerControlsFailed.
  ///
  /// In en, this message translates to:
  /// **'Reader controls could not be displayed. Try again.'**
  String get readerControlsFailed;

  /// No description provided for @navigationInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Navigation was interrupted. Try again.'**
  String get navigationInterrupted;

  /// No description provided for @outline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outline;

  /// No description provided for @noOutline.
  ///
  /// In en, this message translates to:
  /// **'No outline supplied by this publication.'**
  String get noOutline;

  /// No description provided for @sidebarViewMenu.
  ///
  /// In en, this message translates to:
  /// **'Sidebar View'**
  String get sidebarViewMenu;

  /// No description provided for @outlineGroupLocation.
  ///
  /// In en, this message translates to:
  /// **'Section group without a navigation destination.'**
  String get outlineGroupLocation;

  /// No description provided for @noPublisherPage.
  ///
  /// In en, this message translates to:
  /// **'No publisher page reference is available for this location.'**
  String get noPublisherPage;

  /// No description provided for @expandSection.
  ///
  /// In en, this message translates to:
  /// **'Expand section'**
  String get expandSection;

  /// No description provided for @collapseSection.
  ///
  /// In en, this message translates to:
  /// **'Collapse section'**
  String get collapseSection;

  /// No description provided for @outlineLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String outlineLevel(int level);

  /// No description provided for @thumbnailFailed.
  ///
  /// In en, this message translates to:
  /// **'Page preview could not be loaded.'**
  String get thumbnailFailed;

  /// No description provided for @loadingOutline.
  ///
  /// In en, this message translates to:
  /// **'Loading outline…'**
  String get loadingOutline;

  /// No description provided for @outlineFailed.
  ///
  /// In en, this message translates to:
  /// **'The publication outline could not be loaded.'**
  String get outlineFailed;

  /// No description provided for @thumbnailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Page previews are unavailable while the book cannot be read.'**
  String get thumbnailUnavailable;

  /// No description provided for @menuOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the menu. Try again.'**
  String get menuOpenFailed;

  /// No description provided for @navigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigation;

  /// No description provided for @annotationActions.
  ///
  /// In en, this message translates to:
  /// **'Annotation Actions'**
  String get annotationActions;

  /// No description provided for @searchThisBook.
  ///
  /// In en, this message translates to:
  /// **'Search in This Book'**
  String get searchThisBook;

  /// No description provided for @lookUp.
  ///
  /// In en, this message translates to:
  /// **'Look Up'**
  String get lookUp;

  /// No description provided for @openFullEntry.
  ///
  /// In en, this message translates to:
  /// **'Open Full Entry'**
  String get openFullEntry;

  /// No description provided for @lookupSource.
  ///
  /// In en, this message translates to:
  /// **'English Wiktionary · Online'**
  String get lookupSource;

  /// No description provided for @lookupLoading.
  ///
  /// In en, this message translates to:
  /// **'Looking up the complete selection…'**
  String get lookupLoading;

  /// No description provided for @lookupMissing.
  ///
  /// In en, this message translates to:
  /// **'No Wiktionary entry matches this complete selection. Try a dictionary form or an established phrase.'**
  String get lookupMissing;

  /// No description provided for @lookupOffline.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to Wiktionary. Check your connection and retry.'**
  String get lookupOffline;

  /// No description provided for @lookupTimeout.
  ///
  /// In en, this message translates to:
  /// **'Wiktionary took too long to respond. Try again.'**
  String get lookupTimeout;

  /// No description provided for @lookupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Wiktionary is unavailable. Try again later.'**
  String get lookupUnavailable;

  /// No description provided for @lookupInvalid.
  ///
  /// In en, this message translates to:
  /// **'Wiktionary returned an unsupported or invalid response. Try again or open the full entry when available.'**
  String get lookupInvalid;

  /// No description provided for @lookupUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This selection or entry cannot be shown as a short definition. Select a word or short phrase (up to 256 characters), or open the full entry when available.'**
  String get lookupUnsupported;

  /// No description provided for @lookupExcerpt.
  ///
  /// In en, this message translates to:
  /// **'Excerpt with up to two senses per section. Language labels describe the terms; they may differ from the book. Definitions are in English. Open the full entry for all languages and senses.'**
  String get lookupExcerpt;

  /// No description provided for @reflowableDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reflowable Reading Defaults'**
  String get reflowableDefaults;

  /// No description provided for @searchFonts.
  ///
  /// In en, this message translates to:
  /// **'Search fonts'**
  String get searchFonts;

  /// No description provided for @installedFonts.
  ///
  /// In en, this message translates to:
  /// **'Installed families'**
  String get installedFonts;

  /// No description provided for @installedFont.
  ///
  /// In en, this message translates to:
  /// **'Installed font'**
  String get installedFont;

  /// No description provided for @genericFontCategory.
  ///
  /// In en, this message translates to:
  /// **'Generic category'**
  String get genericFontCategory;

  /// No description provided for @currentFont.
  ///
  /// In en, this message translates to:
  /// **'Current selection'**
  String get currentFont;

  /// No description provided for @loadingFonts.
  ///
  /// In en, this message translates to:
  /// **'Loading fonts…'**
  String get loadingFonts;

  /// No description provided for @refreshFonts.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshFonts;

  /// No description provided for @noMatchingFonts.
  ///
  /// In en, this message translates to:
  /// **'No matching fonts. Try another name.'**
  String get noMatchingFonts;

  /// No description provided for @fontCatalogueFailed.
  ///
  /// In en, this message translates to:
  /// **'Installed fonts could not be loaded. Generic choices are still available.'**
  String get fontCatalogueFailed;

  /// No description provided for @fontPreview.
  ///
  /// In en, this message translates to:
  /// **'Font preview'**
  String get fontPreview;

  /// No description provided for @fontPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'This font could not be previewed.'**
  String get fontPreviewFailed;

  /// No description provided for @fontUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This font is unavailable; using the default font.'**
  String get fontUnavailable;

  /// No description provided for @publisherFontActive.
  ///
  /// In en, this message translates to:
  /// **'Publisher appearance is active. Your custom font is remembered.'**
  String get publisherFontActive;

  /// No description provided for @fontPublisherHelp.
  ///
  /// In en, this message translates to:
  /// **'Choosing a font turns off publisher appearance. Browsing leaves it unchanged.'**
  String get fontPublisherHelp;

  /// No description provided for @fontApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'The font could not be applied. Your choice can be retried.'**
  String get fontApplyFailed;

  /// No description provided for @fontSampleProse.
  ///
  /// In en, this message translates to:
  /// **'A book, 0123456789.'**
  String get fontSampleProse;

  /// No description provided for @fontSampleBold.
  ///
  /// In en, this message translates to:
  /// **'Bold emphasis.'**
  String get fontSampleBold;

  /// No description provided for @fontSampleItalic.
  ///
  /// In en, this message translates to:
  /// **'An italic voice.'**
  String get fontSampleItalic;

  /// No description provided for @noInstalledFonts.
  ///
  /// In en, this message translates to:
  /// **'No installed families are available in this environment.'**
  String get noInstalledFonts;

  /// No description provided for @rememberedFont.
  ///
  /// In en, this message translates to:
  /// **'Saved font'**
  String get rememberedFont;

  /// No description provided for @regionNote.
  ///
  /// In en, this message translates to:
  /// **'Region note'**
  String get regionNote;

  /// No description provided for @regionNotes.
  ///
  /// In en, this message translates to:
  /// **'Region notes'**
  String get regionNotes;

  /// No description provided for @comicDefaults.
  ///
  /// In en, this message translates to:
  /// **'Comic Reading Defaults'**
  String get comicDefaults;

  /// No description provided for @readingDirection.
  ///
  /// In en, this message translates to:
  /// **'Reading direction'**
  String get readingDirection;

  /// No description provided for @directionAuto.
  ///
  /// In en, this message translates to:
  /// **'From book'**
  String get directionAuto;

  /// No description provided for @directionLtr.
  ///
  /// In en, this message translates to:
  /// **'Left to right'**
  String get directionLtr;

  /// No description provided for @directionRtl.
  ///
  /// In en, this message translates to:
  /// **'Right to left'**
  String get directionRtl;

  /// No description provided for @regionInstructions.
  ///
  /// In en, this message translates to:
  /// **'Select a rectangle on one page. Arrow keys move it; Shift+Arrow resizes; Enter confirms; Escape cancels.'**
  String get regionInstructions;

  /// No description provided for @protectedBookHelp.
  ///
  /// In en, this message translates to:
  /// **'Protected books and encrypted archives cannot be opened. Reading data is preserved.'**
  String get protectedBookHelp;

  /// No description provided for @bookResourceLimitHelp.
  ///
  /// In en, this message translates to:
  /// **'This book exceeds a reading resource limit. Details below identify the affected file or resource.'**
  String get bookResourceLimitHelp;

  /// No description provided for @damagedBookHelp.
  ///
  /// In en, this message translates to:
  /// **'The book is damaged or has invalid content. Locate a complete, readable copy of the same original to keep its reading data.'**
  String get damagedBookHelp;

  /// No description provided for @firstPage.
  ///
  /// In en, this message translates to:
  /// **'First page'**
  String get firstPage;

  /// No description provided for @lastPage.
  ///
  /// In en, this message translates to:
  /// **'Last page'**
  String get lastPage;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @marks.
  ///
  /// In en, this message translates to:
  /// **'Marks'**
  String get marks;

  /// No description provided for @bookText.
  ///
  /// In en, this message translates to:
  /// **'Book Text'**
  String get bookText;

  /// No description provided for @chapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get chapters;

  /// No description provided for @searchCategory.
  ///
  /// In en, this message translates to:
  /// **'Search category'**
  String get searchCategory;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close Search'**
  String get closeSearch;

  /// No description provided for @searchNeedsReading.
  ///
  /// In en, this message translates to:
  /// **'Open Reading to search the publication or load page previews.'**
  String get searchNeedsReading;

  /// No description provided for @enterSearch.
  ///
  /// In en, this message translates to:
  /// **'Enter text to search.'**
  String get enterSearch;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @allTypes.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get allTypes;

  /// No description provided for @bookOrder.
  ///
  /// In en, this message translates to:
  /// **'Book Order'**
  String get bookOrder;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @noNotebookResults.
  ///
  /// In en, this message translates to:
  /// **'No items match these filters.'**
  String get noNotebookResults;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear Filters'**
  String get clearFilters;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @showFullNote.
  ///
  /// In en, this message translates to:
  /// **'Show Full Note'**
  String get showFullNote;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show Less'**
  String get showLess;

  /// No description provided for @bookActions.
  ///
  /// In en, this message translates to:
  /// **'Book Actions'**
  String get bookActions;

  /// No description provided for @aboutBusyBooks.
  ///
  /// In en, this message translates to:
  /// **'About BusyBooks'**
  String get aboutBusyBooks;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @systemControlled.
  ///
  /// In en, this message translates to:
  /// **'Controlled by your system'**
  String get systemControlled;

  /// No description provided for @motionReduced.
  ///
  /// In en, this message translates to:
  /// **'Reduced'**
  String get motionReduced;

  /// No description provided for @motionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Animations enabled'**
  String get motionEnabled;

  /// No description provided for @moreReadingSettings.
  ///
  /// In en, this message translates to:
  /// **'More Reading Settings…'**
  String get moreReadingSettings;

  /// No description provided for @pageDestination.
  ///
  /// In en, this message translates to:
  /// **'Page number or printed label'**
  String get pageDestination;

  /// No description provided for @pageDestinationHelp.
  ///
  /// In en, this message translates to:
  /// **'Numbers select physical pages. Use =label for a printed label.'**
  String get pageDestinationHelp;

  /// No description provided for @bareBookmarks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 bookmark without notes} other{{count} bookmarks without notes}}'**
  String bareBookmarks(int count);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @readingDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reading defaults'**
  String get readingDefaults;

  /// No description provided for @closeCollection.
  ///
  /// In en, this message translates to:
  /// **'Close Collection'**
  String get closeCollection;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @anyNotes.
  ///
  /// In en, this message translates to:
  /// **'Any notes'**
  String get anyNotes;

  /// No description provided for @dateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Date unavailable'**
  String get dateUnavailable;

  /// No description provided for @regionPreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Region preview unavailable. The private note is still accessible.'**
  String get regionPreviewUnavailable;

  /// No description provided for @regionPreviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading region preview'**
  String get regionPreviewLoading;

  /// No description provided for @searchBooks.
  ///
  /// In en, this message translates to:
  /// **'Search Books'**
  String get searchBooks;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Search Recent'**
  String get searchRecent;

  /// No description provided for @searchBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Search Bookmarks'**
  String get searchBookmarks;

  /// No description provided for @searchChapters.
  ///
  /// In en, this message translates to:
  /// **'Search Chapters'**
  String get searchChapters;

  /// No description provided for @searchBookText.
  ///
  /// In en, this message translates to:
  /// **'Search Book Text'**
  String get searchBookText;

  /// No description provided for @thisBook.
  ///
  /// In en, this message translates to:
  /// **'This Book'**
  String get thisBook;

  /// No description provided for @currentCollection.
  ///
  /// In en, this message translates to:
  /// **'Current Collection'**
  String get currentCollection;

  /// No description provided for @allSavedBooks.
  ///
  /// In en, this message translates to:
  /// **'All Saved Books'**
  String get allSavedBooks;

  /// No description provided for @searchScope.
  ///
  /// In en, this message translates to:
  /// **'Search scope'**
  String get searchScope;

  /// No description provided for @showMoreResults.
  ///
  /// In en, this message translates to:
  /// **'Show more results'**
  String get showMoreResults;

  /// No description provided for @searchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Search source is unavailable'**
  String get searchUnavailable;

  /// No description provided for @searchIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Results are incomplete'**
  String get searchIncomplete;

  /// No description provided for @searchDisabled.
  ///
  /// In en, this message translates to:
  /// **'Unavailable in this context'**
  String get searchDisabled;

  /// No description provided for @searchContext.
  ///
  /// In en, this message translates to:
  /// **'Search:'**
  String get searchContext;

  /// No description provided for @searchLoadedResults.
  ///
  /// In en, this message translates to:
  /// **'{count} results shown'**
  String searchLoadedResults(int count);

  /// No description provided for @searchMoreAvailable.
  ///
  /// In en, this message translates to:
  /// **'More results are available.'**
  String get searchMoreAvailable;

  /// No description provided for @searchEarlierResults.
  ///
  /// In en, this message translates to:
  /// **'Earlier results are outside this window. Search again to return to the beginning.'**
  String get searchEarlierResults;

  /// No description provided for @split.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get split;

  /// No description provided for @resizeSplitPanes.
  ///
  /// In en, this message translates to:
  /// **'Resize Reading and Notebook panes'**
  String get resizeSplitPanes;

  /// No description provided for @splitPaneRatio.
  ///
  /// In en, this message translates to:
  /// **'Reading {reading}%, Notebook {notebook}%'**
  String splitPaneRatio(int reading, int notebook);

  /// No description provided for @resizeSplitPanesHelp.
  ///
  /// In en, this message translates to:
  /// **'Use Left and Right arrow keys to resize panes.'**
  String get resizeSplitPanesHelp;

  /// No description provided for @splitMinimumWidth.
  ///
  /// In en, this message translates to:
  /// **'Needs {width} px of content width.'**
  String splitMinimumWidth(int width);

  /// No description provided for @splitCollapsed.
  ///
  /// In en, this message translates to:
  /// **'Split temporarily shows {pane} while space is limited.'**
  String splitCollapsed(String pane);

  /// No description provided for @showSplitPane.
  ///
  /// In en, this message translates to:
  /// **'Show {pane}'**
  String showSplitPane(String pane);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
