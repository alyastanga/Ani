import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
    Locale('en'),
    Locale('fil'),
  ];

  /// The application title
  ///
  /// In en, this message translates to:
  /// **'Ani'**
  String get appTitle;

  /// Onboarding step 1 title
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get onboardingLanguageTitle;

  /// Onboarding step 1 subtitle
  ///
  /// In en, this message translates to:
  /// **'You can change this later in settings.'**
  String get onboardingLanguageSubtitle;

  /// Language option; shown in its own language in both locales
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language option; shown in its own language in both locales
  ///
  /// In en, this message translates to:
  /// **'Filipino'**
  String get languageFilipino;

  /// Onboarding step 2 title (town picker)
  ///
  /// In en, this message translates to:
  /// **'Where is your farm?'**
  String get onboardingTownTitle;

  /// Onboarding step 2 subtitle
  ///
  /// In en, this message translates to:
  /// **'We use the weather and soil data for your town.'**
  String get onboardingTownSubtitle;

  /// Town name (proper noun, same in both locales)
  ///
  /// In en, this message translates to:
  /// **'Guimba'**
  String get townGuimba;

  /// Town name (proper noun, same in both locales)
  ///
  /// In en, this message translates to:
  /// **'Science City of Muñoz'**
  String get townMunoz;

  /// Town name (proper noun, same in both locales)
  ///
  /// In en, this message translates to:
  /// **'Bongabon'**
  String get townBongabon;

  /// Primary button to go to the next onboarding step
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// Button to go to the previous onboarding step
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Onboarding progress label
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onboardingStepOf(int step, int total);

  /// Bottom nav tab: Start/Home screen
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom nav tab: season outlook
  ///
  /// In en, this message translates to:
  /// **'Outlook'**
  String get navOutlook;

  /// Bottom nav tab: crop library
  ///
  /// In en, this message translates to:
  /// **'Crops'**
  String get navCrops;

  /// Bottom nav tab: tracked plantings
  ///
  /// In en, this message translates to:
  /// **'My farm'**
  String get navMyFarm;

  /// Placeholder text for screens not built yet
  ///
  /// In en, this message translates to:
  /// **'This screen is coming soon.'**
  String get comingSoon;

  /// Settings sheet title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings action: re-pick the town
  ///
  /// In en, this message translates to:
  /// **'Change town'**
  String get settingsChangeTown;

  /// Settings action: re-pick the language
  ///
  /// In en, this message translates to:
  /// **'Change language'**
  String get settingsChangeLanguage;

  /// About page title
  ///
  /// In en, this message translates to:
  /// **'About and limits'**
  String get aboutTitle;

  /// Settings row subtitle
  ///
  /// In en, this message translates to:
  /// **'What Ani can and cannot tell you'**
  String get aboutLinkSubtitle;

  /// About: limits section eyebrow
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get aboutLimitsHeading;

  /// About limit 1
  ///
  /// In en, this message translates to:
  /// **'One point per town: advice uses a single weather and soil point for the whole municipality, not your own field.'**
  String get aboutLimitPoint;

  /// About limit 2
  ///
  /// In en, this message translates to:
  /// **'Advisory only: Ani suggests, it does not decide. Check with your Municipal Agriculture Office (MAO) before acting.'**
  String get aboutLimitAdvisory;

  /// About limit 3
  ///
  /// In en, this message translates to:
  /// **'The rice water need shown is a lower bound: real fields lose more to seepage, percolation and land preparation.'**
  String get aboutLimitRice;

  /// About limit 4
  ///
  /// In en, this message translates to:
  /// **'Not tested in field trials: results come from models and records, and have not been checked on farms.'**
  String get aboutLimitTrials;

  /// About limit 5
  ///
  /// In en, this message translates to:
  /// **'Heat safety is advice for people only; it is never used in crop decisions.'**
  String get aboutLimitHeat;

  /// About: sources eyebrow
  ///
  /// In en, this message translates to:
  /// **'Data sources'**
  String get aboutSourcesHeading;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'NASA POWER: daily weather for each town, synced when you are online.'**
  String get aboutSourcePower;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'ISRIC SoilGrids 2.0: soil properties for each town.'**
  String get aboutSourceSoil;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'NOAA CPC RONI: El Niño and La Niña tag for each dry season.'**
  String get aboutSourceEnso;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'FAO-56: crop water use and growth stages.'**
  String get aboutSourceFao;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'PSA OpenSTAT and PSA costs and returns: past yields and prices.'**
  String get aboutSourcePsa;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'PAGASA: heat index categories for the heat safety advice.'**
  String get aboutSourcePagasa;

  /// About source
  ///
  /// In en, this message translates to:
  /// **'MAO referral: for low-confidence results, Ani points you to your Municipal Agriculture Office.'**
  String get aboutSourceMao;

  /// Crop name (rice); Filipino name used in both locales, from planner.NAME
  ///
  /// In en, this message translates to:
  /// **'Palay'**
  String get cropPalay;

  /// Crop name (onion); Filipino name used in both locales, from planner.NAME
  ///
  /// In en, this message translates to:
  /// **'Sibuyas'**
  String get cropSibuyas;

  /// Crop name (mung bean); Filipino name used in both locales, from planner.NAME
  ///
  /// In en, this message translates to:
  /// **'Munggo'**
  String get cropMunggo;

  /// Crop name (maize); Filipino name used in both locales, from planner.NAME
  ///
  /// In en, this message translates to:
  /// **'Mais'**
  String get cropMais;

  /// Crop name (sweet potato); Filipino name used in both locales, from planner.NAME
  ///
  /// In en, this message translates to:
  /// **'Kamote'**
  String get cropKamote;

  /// English gloss for Palay; UI may show it next to the name in English only
  ///
  /// In en, this message translates to:
  /// **'Rice'**
  String get cropPalayGloss;

  /// English gloss for Sibuyas; UI may show it next to the name in English only
  ///
  /// In en, this message translates to:
  /// **'Onion'**
  String get cropSibuyasGloss;

  /// English gloss for Munggo; UI may show it next to the name in English only
  ///
  /// In en, this message translates to:
  /// **'Mung bean'**
  String get cropMunggoGloss;

  /// English gloss for Mais; UI may show it next to the name in English only
  ///
  /// In en, this message translates to:
  /// **'Maize'**
  String get cropMaisGloss;

  /// English gloss for Kamote; UI may show it next to the name in English only
  ///
  /// In en, this message translates to:
  /// **'Sweet potato'**
  String get cropKamoteGloss;

  /// Hold screen title; doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Huwag munang magtanim'**
  String get holdTitle;

  /// Label for the reasons on a crop card; doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Bakit?'**
  String get whyLabel;

  /// Dryness alert level; doc-quoted, same in both locales
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get dryNormal;

  /// Dryness alert level (watch); doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Bantay'**
  String get dryBantay;

  /// Dryness alert level (danger); doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Delikado'**
  String get dryDelikado;

  /// Referral to the Municipal Agriculture Office; doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Kumonsulta sa MAO'**
  String get consultMao;

  /// Heat safety advice on danger days; doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Magtrabaho nang maaga'**
  String get workEarly;

  /// El Niño outlook headline; doc-quoted, Filipino in both locales
  ///
  /// In en, this message translates to:
  /// **'Inaasahan ang El Niño ngayong tag-araw'**
  String get elNinoExpected;

  /// Home call-to-action that opens the recommendation questionnaire
  ///
  /// In en, this message translates to:
  /// **'What should I plant?'**
  String get homeCta;

  /// Home card title for the El Niño season outlook
  ///
  /// In en, this message translates to:
  /// **'Dry-season outlook'**
  String get homeOutlookTitle;

  /// Home card title for the tracked-crop summary
  ///
  /// In en, this message translates to:
  /// **'Your crop'**
  String get homeTrackedTitle;

  /// Empty state for the tracked-crop summary
  ///
  /// In en, this message translates to:
  /// **'No crop tracked yet.'**
  String get homeTrackedEmpty;

  /// Alerts list title
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsTitle;

  /// Empty state for the alerts list
  ///
  /// In en, this message translates to:
  /// **'No alerts right now.'**
  String get alertsEmpty;

  /// ENSO phase tag
  ///
  /// In en, this message translates to:
  /// **'El Niño'**
  String get ensoElNino;

  /// ENSO phase tag
  ///
  /// In en, this message translates to:
  /// **'La Niña'**
  String get ensoLaNina;

  /// ENSO phase tag
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get ensoNeutral;

  /// Plain-word strength of the El Niño / La Niña signal (replaces the raw JAS index)
  ///
  /// In en, this message translates to:
  /// **'{level, select, weak{Weak} moderate{Moderate} strong{Strong} veryStrong{Very strong} other{}}'**
  String ensoStrength(String level);

  /// Title of the dryness banner/chart
  ///
  /// In en, this message translates to:
  /// **'Dryness'**
  String get drynessTitle;

  /// Rank sentence under the dryness banner: this season is the rank-th driest of n years on record
  ///
  /// In en, this message translates to:
  /// **'{rank, plural, =1{Driest} other{No. {rank} driest}} of {n, plural, =1{1 year} other{{n} years}}'**
  String drynessRank(int rank, int n);

  /// Outlook chart title
  ///
  /// In en, this message translates to:
  /// **'Monthly dryness index'**
  String get drynessChartTitle;

  /// Chart legend for El Niño seasons
  ///
  /// In en, this message translates to:
  /// **'El Niño seasons'**
  String get drynessChartElNino;

  /// Heat safety strip/section title
  ///
  /// In en, this message translates to:
  /// **'Heat safety'**
  String get heatSafetyTitle;

  /// Heat index reading; value is preformatted
  ///
  /// In en, this message translates to:
  /// **'Heat index {value}°C'**
  String heatIndexValue(String value);

  /// PAGASA heat index category
  ///
  /// In en, this message translates to:
  /// **'Caution'**
  String get heatCaution;

  /// PAGASA heat index category
  ///
  /// In en, this message translates to:
  /// **'Extreme caution'**
  String get heatExtremeCaution;

  /// PAGASA heat index category
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get heatDanger;

  /// PAGASA heat index category
  ///
  /// In en, this message translates to:
  /// **'Extreme danger'**
  String get heatExtremeDanger;

  /// Disclaimer under heat safety (doc requirement)
  ///
  /// In en, this message translates to:
  /// **'For people\'s safety only. Not used to choose crops.'**
  String get heatSafetyNote;

  /// Questionnaire progress label
  ///
  /// In en, this message translates to:
  /// **'Question {step} of {total}'**
  String questionStepOf(int step, int total);

  /// Questionnaire step 1
  ///
  /// In en, this message translates to:
  /// **'Which town is your farm in?'**
  String get questionTownTitle;

  /// Questionnaire step 2
  ///
  /// In en, this message translates to:
  /// **'What were your last two crops?'**
  String get questionLastCropsTitle;

  /// Hint for step 2 (two picks: most recent, then the one before)
  ///
  /// In en, this message translates to:
  /// **'Most recent first. Pick None if the field was empty.'**
  String get questionLastCropsHint;

  /// Questionnaire step 3
  ///
  /// In en, this message translates to:
  /// **'How much water can you give?'**
  String get questionWaterTitle;

  /// Water option: rainfed
  ///
  /// In en, this message translates to:
  /// **'Rain only (no irrigation)'**
  String get waterRainfed;

  /// Water option: limited_2
  ///
  /// In en, this message translates to:
  /// **'About 2 irrigations'**
  String get waterLimited2;

  /// Water option: limited_4
  ///
  /// In en, this message translates to:
  /// **'About 4 irrigations'**
  String get waterLimited4;

  /// Water option: full
  ///
  /// In en, this message translates to:
  /// **'Irrigate as needed'**
  String get waterFull;

  /// Questionnaire step 4
  ///
  /// In en, this message translates to:
  /// **'Any crops you won\'t plant?'**
  String get questionWontTitle;

  /// Checkbox in step 4 (affects onion price-risk guard)
  ///
  /// In en, this message translates to:
  /// **'I can use cold storage'**
  String get questionColdStorage;

  /// Questionnaire step 5
  ///
  /// In en, this message translates to:
  /// **'What matters most to you?'**
  String get questionPrioritiesTitle;

  /// Hint for step 5
  ///
  /// In en, this message translates to:
  /// **'Tap your top 3, most important first.'**
  String get questionPrioritiesHint;

  /// Priority option
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get priorityIncome;

  /// Priority option
  ///
  /// In en, this message translates to:
  /// **'Low risk'**
  String get priorityRisk;

  /// Priority option
  ///
  /// In en, this message translates to:
  /// **'Saves water'**
  String get priorityWater;

  /// Priority option
  ///
  /// In en, this message translates to:
  /// **'Soil health'**
  String get prioritySoil;

  /// Priority option
  ///
  /// In en, this message translates to:
  /// **'Fewer pests'**
  String get priorityPest;

  /// Choice meaning no crop / nothing
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get answerNone;

  /// Final questionnaire button
  ///
  /// In en, this message translates to:
  /// **'See advice'**
  String get questionSeeResult;

  /// Result screen title
  ///
  /// In en, this message translates to:
  /// **'Suggested crops'**
  String get resultTitle;

  /// Crop risk line: number of failed seasons out of simulated seasons
  ///
  /// In en, this message translates to:
  /// **'Failed in {failed} of {seasons, plural, =1{1 year} other{{seasons} years}}'**
  String cardFailedSeasons(int failed, int seasons);

  /// Wilson interval for the failure rate; values are preformatted percents
  ///
  /// In en, this message translates to:
  /// **'Likely range {low}–{high}'**
  String cardFailRange(String low, String high);

  /// Season water need
  ///
  /// In en, this message translates to:
  /// **'Water needed: {mm} mm'**
  String cardWaterNeeded(int mm);

  /// Net income p10-p90; values are preformatted with the peso sign, e.g. '−₱12,300'
  ///
  /// In en, this message translates to:
  /// **'Net income: {low} to {high} per hectare'**
  String cardNetIncome(String low, String high);

  /// Label before confidence level
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get confidenceLabel;

  /// Confidence level
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get confidenceHigh;

  /// Confidence level
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get confidenceMedium;

  /// Confidence level
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get confidenceLow;

  /// Shown with the MAO referral on Low confidence cards
  ///
  /// In en, this message translates to:
  /// **'Low confidence. Please check with your Municipal Agriculture Office.'**
  String get lowConfidenceNote;

  /// Onion price-risk warning (guard g3)
  ///
  /// In en, this message translates to:
  /// **'No cold storage: high price risk'**
  String get onionPriceWarning;

  /// Hold screen label before the blocking guard's reason
  ///
  /// In en, this message translates to:
  /// **'Why not now'**
  String get holdReasonLabel;

  /// Hold screen tip (fil text from planner.hold_message)
  ///
  /// In en, this message translates to:
  /// **'Cover the soil with straw (mulch) or let it rest, and get irrigation ready for next season.'**
  String get holdTip;

  /// Button on a crop card to start tracking
  ///
  /// In en, this message translates to:
  /// **'Track this crop'**
  String get resultTrackThis;

  /// Button to restart the questionnaire
  ///
  /// In en, this message translates to:
  /// **'Answer again'**
  String get resultStartOver;

  /// My farm: add a planting
  ///
  /// In en, this message translates to:
  /// **'Add planting'**
  String get myFarmAddPlanting;

  /// Planting form field
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get plantingCrop;

  /// Planting form field
  ///
  /// In en, this message translates to:
  /// **'Planting date'**
  String get plantingDate;

  /// Planting form field
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get plantingMethod;

  /// Planting method option
  ///
  /// In en, this message translates to:
  /// **'Direct seeding'**
  String get methodDirectSeed;

  /// Planting method option
  ///
  /// In en, this message translates to:
  /// **'Transplanting'**
  String get methodTransplant;

  /// Planting form field (defaults from profile)
  ///
  /// In en, this message translates to:
  /// **'Irrigation'**
  String get plantingIrrigation;

  /// Save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get plantingSave;

  /// Field machine stage: land preparation
  ///
  /// In en, this message translates to:
  /// **'Prep'**
  String get stagePrep;

  /// Field machine stage: establishment
  ///
  /// In en, this message translates to:
  /// **'Establishment'**
  String get stageEstab;

  /// Field machine stage: vegetative
  ///
  /// In en, this message translates to:
  /// **'Vegetative'**
  String get stageVeg;

  /// Field machine stage: reproductive
  ///
  /// In en, this message translates to:
  /// **'Flowering'**
  String get stageRepro;

  /// Field machine stage: mature
  ///
  /// In en, this message translates to:
  /// **'Maturing'**
  String get stageMature;

  /// Field machine stage: harvest
  ///
  /// In en, this message translates to:
  /// **'Harvest'**
  String get stageHarvest;

  /// Field machine stage: failed
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stageFailed;

  /// Days since planting
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String trackerDay(int day);

  /// Expected harvest window; dates preformatted
  ///
  /// In en, this message translates to:
  /// **'Expected harvest: {start} – {end}'**
  String expectedHarvest(String start, String end);

  /// Button that confirms harvest (transition 7)
  ///
  /// In en, this message translates to:
  /// **'Confirm harvest'**
  String get confirmHarvest;

  /// Day with no POWER data yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for data'**
  String get waitingForData;

  /// Number of recent days without POWER data
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day waiting for data} other{{count} days waiting for data}}'**
  String waitingForDataDays(int count);

  /// Last sync time; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Updated {date}'**
  String lastUpdated(String date);

  /// Banner when no network
  ///
  /// In en, this message translates to:
  /// **'Offline: using saved data'**
  String get offlineNote;

  /// Label for demo mode
  ///
  /// In en, this message translates to:
  /// **'Replay of a past season'**
  String get demoReplayLabel;

  /// Alert title
  ///
  /// In en, this message translates to:
  /// **'Water now'**
  String get alertWaterNow;

  /// Alert body
  ///
  /// In en, this message translates to:
  /// **'The soil is drying out. Irrigate in the next day or two.'**
  String get alertWaterNowBody;

  /// Alert title
  ///
  /// In en, this message translates to:
  /// **'Heat at flowering'**
  String get alertHeatFlowering;

  /// Alert body
  ///
  /// In en, this message translates to:
  /// **'Very hot days during flowering can lower your harvest. Keep the soil moist.'**
  String get alertHeatFloweringBody;

  /// Alert title
  ///
  /// In en, this message translates to:
  /// **'Onion rot risk'**
  String get alertOnionRot;

  /// Alert body
  ///
  /// In en, this message translates to:
  /// **'The soil is too wet. Hold off on watering and let the field drain.'**
  String get alertOnionRotBody;

  /// Alert title
  ///
  /// In en, this message translates to:
  /// **'Crop failed'**
  String get alertFailed;

  /// Alert body
  ///
  /// In en, this message translates to:
  /// **'The crop is unlikely to recover this season.'**
  String get alertFailedBody;

  /// Alert title
  ///
  /// In en, this message translates to:
  /// **'Ready to harvest'**
  String get alertHarvestReady;

  /// Alert body
  ///
  /// In en, this message translates to:
  /// **'Your crop has reached maturity. Confirm when you harvest.'**
  String get alertHarvestReadyBody;

  /// Crop library title
  ///
  /// In en, this message translates to:
  /// **'Crop library'**
  String get libraryTitle;

  /// Crop duration
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String cropDurationDays(int days);

  /// Library field
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get cropDurationLabel;

  /// Library field
  ///
  /// In en, this message translates to:
  /// **'Sowing window'**
  String get cropSowingWindow;

  /// Library field (plant family)
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get cropFamily;

  /// Library field
  ///
  /// In en, this message translates to:
  /// **'Water need'**
  String get cropWaterNeed;

  /// Library table title
  ///
  /// In en, this message translates to:
  /// **'Failed seasons by irrigation'**
  String get cropRiskByIrrigation;

  /// Library header under the title
  ///
  /// In en, this message translates to:
  /// **'Five dry-season crops for {town}'**
  String cropLibrarySubtitle(String town);

  /// Sowing window as two short dates
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String cropSowWindowRange(String start, String end);

  /// Library water need level
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get cropWaterNeedHigh;

  /// Library water need level
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get cropWaterNeedMedium;

  /// Library water need level
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get cropWaterNeedLow;

  /// Library detail note on rice water need
  ///
  /// In en, this message translates to:
  /// **'For rice this is a lower bound; real need is higher.'**
  String get cropWaterNeedRiceNote;

  /// Library detail chip
  ///
  /// In en, this message translates to:
  /// **'A legume: it adds nitrogen to the soil.'**
  String get cropLegumeNote;

  /// Library detail chip
  ///
  /// In en, this message translates to:
  /// **'Small local market: check buyers before planting.'**
  String get cropSmallMarketNote;

  /// Failed seasons out of the baseline seasons
  ///
  /// In en, this message translates to:
  /// **'Failed {x} of {n}'**
  String cropFailedOf(int x, int n);

  /// Library table column
  ///
  /// In en, this message translates to:
  /// **'El Niño seasons'**
  String get cropRiskElNinoSeasons;

  /// Library table column
  ///
  /// In en, this message translates to:
  /// **'Other seasons'**
  String get cropRiskOtherSeasons;

  /// Library table first column
  ///
  /// In en, this message translates to:
  /// **'Irrigation'**
  String get cropRiskIrrigationColumn;

  /// Library table footnote
  ///
  /// In en, this message translates to:
  /// **'Counted over past dry seasons (2001 to 2025) at one point in {town}. This is a guide, not a promise.'**
  String cropRiskNote(String town);

  /// About page limits paragraph
  ///
  /// In en, this message translates to:
  /// **'Ani gives advice only. Weather is from one point per town, and rice water need is a lower bound. Results were not tested in the field.'**
  String get aboutAdvisory;

  /// Data sources
  ///
  /// In en, this message translates to:
  /// **'Data: NASA POWER, ISRIC SoilGrids, NOAA CPC, PSA.'**
  String get aboutSources;

  /// Retry button
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// Close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Error card when the bundled town JSON fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load the data for this town.'**
  String get bundleLoadError;

  /// Home: number of crops in the loaded bundle
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 crop in this town\'s data} other{{count} crops in this town\'s data}}'**
  String homeCropCount(int count);

  /// Questionnaire and result screen header
  ///
  /// In en, this message translates to:
  /// **'What should I plant?'**
  String get recommendTitle;

  /// Step 2 section: the most recent crop
  ///
  /// In en, this message translates to:
  /// **'Most recent crop'**
  String get questionLastCropRecent;

  /// Step 2 section: the crop before the most recent
  ///
  /// In en, this message translates to:
  /// **'The crop before that'**
  String get questionLastCropBefore;

  /// Step 3 section: water source
  ///
  /// In en, this message translates to:
  /// **'Where does your water come from?'**
  String get questionWaterSourceLabel;

  /// Step 3 section: number of irrigations (planner water level)
  ///
  /// In en, this message translates to:
  /// **'How many times can you irrigate this dry season?'**
  String get questionIrrigationsLabel;

  /// Water source option
  ///
  /// In en, this message translates to:
  /// **'Rain only'**
  String get sourceRain;

  /// Water source option
  ///
  /// In en, this message translates to:
  /// **'Pump or shallow tube well'**
  String get sourcePump;

  /// Water source option
  ///
  /// In en, this message translates to:
  /// **'Irrigation canal (NIA or communal)'**
  String get sourceCanal;

  /// Water source option
  ///
  /// In en, this message translates to:
  /// **'River, creek or pond'**
  String get sourceRiver;

  /// Hint for step 4
  ///
  /// In en, this message translates to:
  /// **'Tap any you will not plant. Leave all empty if none.'**
  String get questionWontHint;

  /// Step 4 section heading
  ///
  /// In en, this message translates to:
  /// **'Cold storage'**
  String get questionColdStorageLabel;

  /// Subtitle of the cold storage choice
  ///
  /// In en, this message translates to:
  /// **'Matters for onion (Sibuyas) prices.'**
  String get questionColdStorageHint;

  /// Step 5 counter
  ///
  /// In en, this message translates to:
  /// **'{count} of 3 picked'**
  String questionPrioritiesPicked(int count);

  /// Crop risk line in El Niño mode (failure counted over El Niño seasons)
  ///
  /// In en, this message translates to:
  /// **'Failed in {failed} of {seasons} El Niño years'**
  String cardFailedSeasonsElNino(int failed, int seasons);

  /// Rank badge on a crop card
  ///
  /// In en, this message translates to:
  /// **'No. {rank}'**
  String cardRank(int rank);

  /// Confidence pill; level is confidenceHigh/Medium/Low
  ///
  /// In en, this message translates to:
  /// **'Confidence: {level}'**
  String cardConfidence(String level);

  /// Flag for crops with a thin local market
  ///
  /// In en, this message translates to:
  /// **'Small local market: check with the MAO'**
  String get cardSmallMarket;

  /// Result screen subtitle: town and water answer
  ///
  /// In en, this message translates to:
  /// **'{town} · {water}'**
  String resultSubtitle(String town, String water);

  /// Note that El Niño mode raised the water and risk weights
  ///
  /// In en, this message translates to:
  /// **'El Niño year: water and risk count more'**
  String get resultElNinoMode;

  /// Close the result screen
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get resultDone;

  /// Note under the result
  ///
  /// In en, this message translates to:
  /// **'Your answers are saved on this phone.'**
  String get resultSaved;

  /// Crops removed by the blocking guard; crops is a comma-separated list
  ///
  /// In en, this message translates to:
  /// **'Ruled out: {crops}'**
  String holdRemovedCrops(String crops);

  /// Hold screen label before the tip
  ///
  /// In en, this message translates to:
  /// **'What you can do'**
  String get holdTipLabel;

  /// Hold reason for guard g2 (English locale; Filipino shows planner text)
  ///
  /// In en, this message translates to:
  /// **'The chance of crop failure is too high for your water supply this El Niño.'**
  String get holdGuardWater;

  /// Hold reason for guard g4
  ///
  /// In en, this message translates to:
  /// **'No crop is left after removing the ones you won\'t plant.'**
  String get holdGuardFarmer;

  /// Hold reason for guard g5
  ///
  /// In en, this message translates to:
  /// **'It is too hot at flowering time.'**
  String get holdGuardHeat;

  /// Hold reason for guard g6
  ///
  /// In en, this message translates to:
  /// **'No crop is expected to make a profit this dry season with your water.'**
  String get holdGuardProfit;

  /// Hold reason for guard g1
  ///
  /// In en, this message translates to:
  /// **'No crop suits the dry season.'**
  String get holdGuardSeason;

  /// Shown when reopening a recommendation with nothing saved
  ///
  /// In en, this message translates to:
  /// **'No saved answers yet.'**
  String get recommendNoSaved;

  /// Home secondary button that reopens the last saved recommendation
  ///
  /// In en, this message translates to:
  /// **'See last recommendation'**
  String get homeLastRecommendation;

  /// Eyebrow above the saved recommendation summary on Home
  ///
  /// In en, this message translates to:
  /// **'Last recommendation'**
  String get homeLastRecommendationTitle;

  /// Rank sentence when the dryness index is below zero: this month is the rank-th wettest of n years on record
  ///
  /// In en, this message translates to:
  /// **'{rank, plural, =1{Wettest} other{No. {rank} wettest}} of {n, plural, =1{1 year} other{{n} years}}'**
  String drynessRankWet(int rank, int n);

  /// Dryness index value on the Home banner; value is preformatted, e.g. 'D -1.45'
  ///
  /// In en, this message translates to:
  /// **'D {value}'**
  String drynessDValue(String value);

  /// Heat-safety strip lead-in before 'Magtrabaho nang maaga'; category is the PAGASA danger category name, value its lower bound
  ///
  /// In en, this message translates to:
  /// **'On {category} days (heat index {value}°C and up):'**
  String homeHeatDangerFrom(String category, String value);

  /// Hint under the empty tracked-crop state on Home
  ///
  /// In en, this message translates to:
  /// **'Track a planting to see its stage and alerts here.'**
  String get homeTrackedHint;

  /// My farm empty state title
  ///
  /// In en, this message translates to:
  /// **'No plantings yet'**
  String get myFarmEmptyTitle;

  /// My farm empty state hint
  ///
  /// In en, this message translates to:
  /// **'Add the crop you planted to follow its stages and get alerts.'**
  String get myFarmEmptyHint;

  /// My farm section: open plantings
  ///
  /// In en, this message translates to:
  /// **'Growing now'**
  String get myFarmGrowing;

  /// My farm section: closed plantings
  ///
  /// In en, this message translates to:
  /// **'Past seasons'**
  String get myFarmPast;

  /// Planting date line; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Planted {date}'**
  String plantingPlantedOn(String date);

  /// Tag on demo replay rows
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get plantingDemoTag;

  /// Season progress (growing degree days so far / needed)
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the season'**
  String plantingProgress(int percent);

  /// Last real POWER day replayed; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Weather data up to {date}'**
  String plantingLastData(String date);

  /// No POWER day replayed yet
  ///
  /// In en, this message translates to:
  /// **'No weather data yet'**
  String get plantingNoDataYet;

  /// Explains the waiting-for-data lag
  ///
  /// In en, this message translates to:
  /// **'NASA POWER publishes a few days late. The tracker moves on when the data arrives.'**
  String get waitingForDataNote;

  /// Stage timeline heading
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get plantingStages;

  /// Timeline: stage not reached
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get stageNotYet;

  /// Timeline: current stage marker
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get stageNow;

  /// Ready-to-harvest date; preformatted
  ///
  /// In en, this message translates to:
  /// **'Ready since {date}'**
  String plantingReadySince(String date);

  /// Closed planting: harvest outcome; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Harvested on {date}'**
  String outcomeHarvested(String date);

  /// Closed planting: failed outcome; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Crop failed on {date}'**
  String outcomeFailed(String date);

  /// Button to delete a planting
  ///
  /// In en, this message translates to:
  /// **'Remove planting'**
  String get plantingRemove;

  /// Confirm dialog for removing a planting
  ///
  /// In en, this message translates to:
  /// **'Remove this planting and its alerts? Past harvest records stay.'**
  String get plantingRemoveConfirm;

  /// Destructive confirm button
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// Detail: no alerts yet
  ///
  /// In en, this message translates to:
  /// **'No alerts for this crop.'**
  String get plantingNoAlerts;

  /// Add planting: method note
  ///
  /// In en, this message translates to:
  /// **'Only matters for onion: its season is counted from transplanting.'**
  String get plantingMethodHint;

  /// Add planting: irrigation prefilled from profile
  ///
  /// In en, this message translates to:
  /// **'Filled in from your last planner answers. Change it if needed.'**
  String get plantingIrrigationHint;

  /// Add planting: town field
  ///
  /// In en, this message translates to:
  /// **'Town'**
  String get plantingTownLabel;

  /// Snackbar after adding a planting
  ///
  /// In en, this message translates to:
  /// **'Planting saved'**
  String get plantingSaved;

  /// Snackbar on save error
  ///
  /// In en, this message translates to:
  /// **'Could not save the planting.'**
  String get plantingSaveError;

  /// Planting detail screen title
  ///
  /// In en, this message translates to:
  /// **'Planting'**
  String get plantingDetailTitle;

  /// Tracker status while syncing POWER
  ///
  /// In en, this message translates to:
  /// **'Updating weather…'**
  String get syncUpdating;

  /// Badge on unseen alerts
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get alertsNew;

  /// Collapsed water-now alerts count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{once} other{{count} times}}'**
  String alertsTimes(int count);

  /// Home: open the alerts list
  ///
  /// In en, this message translates to:
  /// **'See all alerts'**
  String get alertsSeeAll;

  /// Bell semantics label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new alert} other{{count} new alerts}}'**
  String alertsUnseenCount(int count);

  /// Water-now alert body when the crop is already stressed
  ///
  /// In en, this message translates to:
  /// **'The crop is short of water. Irrigate as soon as you can; if you cannot, cover the soil with straw.'**
  String get alertWaterStressBody;

  /// Demo: alerts note
  ///
  /// In en, this message translates to:
  /// **'Alerts from the replay are not saved and do not notify you.'**
  String get alertsDemoNote;

  /// Home: go to the My farm tab
  ///
  /// In en, this message translates to:
  /// **'Open My farm'**
  String get homeOpenMyFarm;

  /// Demo mode entry and title
  ///
  /// In en, this message translates to:
  /// **'Season replay (demo)'**
  String get demoTitle;

  /// Persistent demo banner
  ///
  /// In en, this message translates to:
  /// **'Replay of a past season – not live data'**
  String get demoBanner;

  /// Demo picker intro
  ///
  /// In en, this message translates to:
  /// **'Pick a past dry season to watch a crop go from planting to harvest in a few taps. Nothing here is saved to your farm.'**
  String get demoPickHint;

  /// Demo season card title
  ///
  /// In en, this message translates to:
  /// **'{crop} in {town}'**
  String demoSeasonTitle(String crop, String town);

  /// Demo season card subtitle
  ///
  /// In en, this message translates to:
  /// **'Dry season {season} · {water}'**
  String demoSeasonSubtitle(String season, String water);

  /// Demo season: alert types it shows
  ///
  /// In en, this message translates to:
  /// **'Shows: {alerts}'**
  String demoShows(String alerts);

  /// Demo progress
  ///
  /// In en, this message translates to:
  /// **'Day {day} of {total}'**
  String demoDayOf(int day, int total);

  /// Simulated today; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Replay date: {date}'**
  String demoDate(String date);

  /// Demo control
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get demoNextDay;

  /// Demo control
  ///
  /// In en, this message translates to:
  /// **'+7 days'**
  String get demoNextWeek;

  /// Demo control: run until harvest-ready or the season ends
  ///
  /// In en, this message translates to:
  /// **'Run to end'**
  String get demoRunToEnd;

  /// Demo control
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get demoRestart;

  /// Demo: season closed
  ///
  /// In en, this message translates to:
  /// **'Replay finished'**
  String get demoEnded;

  /// Demo: load error
  ///
  /// In en, this message translates to:
  /// **'Could not load the replay.'**
  String get demoLoadError;

  /// Questionnaire: last two crops prefilled from outcomes
  ///
  /// In en, this message translates to:
  /// **'Filled in from your harvest records.'**
  String get questionLastCropsFromRecords;

  /// Screen title for the Outlook tab
  ///
  /// In en, this message translates to:
  /// **'Season outlook'**
  String get outlookTitle;

  /// Heading above the list of past dry seasons with their El Niño / La Niña tag
  ///
  /// In en, this message translates to:
  /// **'Past dry seasons'**
  String get outlookPastSeasons;

  /// Heading of the live dryness card on the Outlook tab
  ///
  /// In en, this message translates to:
  /// **'Dryness now'**
  String get outlookLiveTitle;

  /// Source line for live dekadal D; date preformatted
  ///
  /// In en, this message translates to:
  /// **'Live from NASA POWER, as of {date}'**
  String outlookLiveLive(String date);

  /// Source line when only the bundled dryness.latest is available; month like 2025-12
  ///
  /// In en, this message translates to:
  /// **'Saved reading for {month}. Go online for live data.'**
  String outlookLiveBundled(String month);

  /// Heading of the dekad list
  ///
  /// In en, this message translates to:
  /// **'Last 10-day periods'**
  String get outlookDekadsTitle;

  /// 10-day period label, e.g. '11–20 Nov'; month preformatted
  ///
  /// In en, this message translates to:
  /// **'{from}–{to} {month}'**
  String outlookDekadRange(int from, int to, String month);

  /// Marks a 10-day period that is not over yet
  ///
  /// In en, this message translates to:
  /// **'so far'**
  String get outlookDekadPartial;

  /// A 10-day period without enough weather data to score
  ///
  /// In en, this message translates to:
  /// **'not enough data'**
  String get outlookDekadNoData;

  /// Caption under the monthly dryness chart
  ///
  /// In en, this message translates to:
  /// **'Higher means drier. Shaded bands are El Niño dry seasons (Nov–Apr).'**
  String get outlookChartNote;

  /// Chart range label
  ///
  /// In en, this message translates to:
  /// **'Last {n} years'**
  String outlookChartYears(int n);

  /// Date of the latest heat reading; date preformatted
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String heatAsOf(String date);

  /// Heat strip when there is no synced weather
  ///
  /// In en, this message translates to:
  /// **'No live heat reading yet. Connect once to load it.'**
  String get heatNoLive;

  /// Count of PAGASA danger days among the recent readings
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 danger day} other{{count} danger days}} in the last week'**
  String heatDangerDays(int count);

  /// Heading of the recent daily heat readings
  ///
  /// In en, this message translates to:
  /// **'Recent days'**
  String get heatRecentTitle;

  /// Shown with the work-early advice when the latest reading is a danger day
  ///
  /// In en, this message translates to:
  /// **'Danger-level heat. Stay safe.'**
  String get heatDangerToday;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Today\'s conditions'**
  String get todayConditionsTitle;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Clear skies'**
  String get condClear;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Partly cloudy'**
  String get condPartly;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get condCloudy;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get condRain;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Heavy rain'**
  String get condHeavyRain;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Feels like {v}°'**
  String feelsLike(String v);

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get humidityLabel;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'Wind'**
  String get windLabel;

  /// Home 'Today's conditions' card
  ///
  /// In en, this message translates to:
  /// **'{v} km/h'**
  String windKmh(String v);
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
      <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fil':
      return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
