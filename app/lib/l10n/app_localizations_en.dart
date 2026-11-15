// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Ani';

  @override
  String get onboardingLanguageTitle => 'Choose your language';

  @override
  String get onboardingLanguageSubtitle =>
      'You can change this later in settings.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFilipino => 'Filipino';

  @override
  String get onboardingTownTitle => 'Where is your farm?';

  @override
  String get onboardingTownSubtitle =>
      'We use the weather and soil data for your town.';

  @override
  String get townGuimba => 'Guimba';

  @override
  String get townMunoz => 'Science City of Muñoz';

  @override
  String get townBongabon => 'Bongabon';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingBack => 'Back';

  @override
  String onboardingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navOutlook => 'Outlook';

  @override
  String get navCrops => 'Crops';

  @override
  String get navMyFarm => 'My farm';

  @override
  String get comingSoon => 'This screen is coming soon.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsChangeTown => 'Change town';

  @override
  String get settingsChangeLanguage => 'Change language';

  @override
  String get aboutTitle => 'About and limits';

  @override
  String get aboutLinkSubtitle => 'What Ani can and cannot tell you';

  @override
  String get aboutLimitsHeading => 'Limits';

  @override
  String get aboutLimitPoint =>
      'One point per town: advice uses a single weather and soil point for the whole municipality, not your own field.';

  @override
  String get aboutLimitAdvisory =>
      'Advisory only: Ani suggests, it does not decide. Check with your Municipal Agriculture Office (MAO) before acting.';

  @override
  String get aboutLimitRice =>
      'The rice water need shown is a lower bound: real fields lose more to seepage, percolation and land preparation.';

  @override
  String get aboutLimitTrials =>
      'Not tested in field trials: results come from models and records, and have not been checked on farms.';

  @override
  String get aboutLimitHeat =>
      'Heat safety is advice for people only; it is never used in crop decisions.';

  @override
  String get aboutSourcesHeading => 'Data sources';

  @override
  String get aboutSourcePower =>
      'NASA POWER: daily weather for each town, synced when you are online.';

  @override
  String get aboutSourceSoil =>
      'ISRIC SoilGrids 2.0: soil properties for each town.';

  @override
  String get aboutSourceEnso =>
      'NOAA CPC RONI: El Niño and La Niña tag for each dry season.';

  @override
  String get aboutSourceFao => 'FAO-56: crop water use and growth stages.';

  @override
  String get aboutSourcePsa =>
      'PSA OpenSTAT and PSA costs and returns: past yields and prices.';

  @override
  String get aboutSourcePagasa =>
      'PAGASA: heat index categories for the heat safety advice.';

  @override
  String get aboutSourceMao =>
      'MAO referral: for low-confidence results, Ani points you to your Municipal Agriculture Office.';

  @override
  String get cropPalay => 'Palay';

  @override
  String get cropSibuyas => 'Sibuyas';

  @override
  String get cropMunggo => 'Munggo';

  @override
  String get cropMais => 'Mais';

  @override
  String get cropKamote => 'Kamote';

  @override
  String get cropPalayGloss => 'Rice';

  @override
  String get cropSibuyasGloss => 'Onion';

  @override
  String get cropMunggoGloss => 'Mung bean';

  @override
  String get cropMaisGloss => 'Maize';

  @override
  String get cropKamoteGloss => 'Sweet potato';

  @override
  String get holdTitle => 'Huwag munang magtanim';

  @override
  String get whyLabel => 'Bakit?';

  @override
  String get dryNormal => 'Normal';

  @override
  String get dryBantay => 'Bantay';

  @override
  String get dryDelikado => 'Delikado';

  @override
  String get consultMao => 'Kumonsulta sa MAO';

  @override
  String get workEarly => 'Magtrabaho nang maaga';

  @override
  String get elNinoExpected => 'Inaasahan ang El Niño ngayong tag-araw';

  @override
  String get homeCta => 'What should I plant?';

  @override
  String get homeOutlookTitle => 'Dry-season outlook';

  @override
  String get homeTrackedTitle => 'Your crop';

  @override
  String get homeTrackedEmpty => 'No crop tracked yet.';

  @override
  String get alertsTitle => 'Alerts';

  @override
  String get alertsEmpty => 'No alerts right now.';

  @override
  String get ensoElNino => 'El Niño';

  @override
  String get ensoLaNina => 'La Niña';

  @override
  String get ensoNeutral => 'Neutral';

  @override
  String ensoStrength(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      'weak': 'Weak',
      'moderate': 'Moderate',
      'strong': 'Strong',
      'veryStrong': 'Very strong',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get drynessTitle => 'Dryness';

  @override
  String drynessRank(int rank, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      rank,
      locale: localeName,
      other: 'No. $rank driest',
      one: 'Driest',
    );
    String _temp1 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years',
      one: '1 year',
    );
    return '$_temp0 of $_temp1';
  }

  @override
  String get drynessChartTitle => 'Monthly dryness index';

  @override
  String get drynessChartElNino => 'El Niño seasons';

  @override
  String get heatSafetyTitle => 'Heat safety';

  @override
  String heatIndexValue(String value) {
    return 'Heat index $value°C';
  }

  @override
  String get heatCaution => 'Caution';

  @override
  String get heatExtremeCaution => 'Extreme caution';

  @override
  String get heatDanger => 'Danger';

  @override
  String get heatExtremeDanger => 'Extreme danger';

  @override
  String get heatSafetyNote =>
      'For people\'s safety only. Not used to choose crops.';

  @override
  String questionStepOf(int step, int total) {
    return 'Question $step of $total';
  }

  @override
  String get questionTownTitle => 'Which town is your farm in?';

  @override
  String get questionLastCropsTitle => 'What were your last two crops?';

  @override
  String get questionLastCropsHint =>
      'Most recent first. Pick None if the field was empty.';

  @override
  String get questionWaterTitle => 'How much water can you give?';

  @override
  String get waterRainfed => 'Rain only (no irrigation)';

  @override
  String get waterLimited2 => 'About 2 irrigations';

  @override
  String get waterLimited4 => 'About 4 irrigations';

  @override
  String get waterFull => 'Irrigate as needed';

  @override
  String get questionWontTitle => 'Any crops you won\'t plant?';

  @override
  String get questionColdStorage => 'I can use cold storage';

  @override
  String get questionPrioritiesTitle => 'What matters most to you?';

  @override
  String get questionPrioritiesHint => 'Tap your top 3, most important first.';

  @override
  String get priorityIncome => 'Income';

  @override
  String get priorityRisk => 'Low risk';

  @override
  String get priorityWater => 'Saves water';

  @override
  String get prioritySoil => 'Soil health';

  @override
  String get priorityPest => 'Fewer pests';

  @override
  String get answerNone => 'None';

  @override
  String get questionSeeResult => 'See advice';

  @override
  String get resultTitle => 'Suggested crops';

  @override
  String cardFailedSeasons(int failed, int seasons) {
    String _temp0 = intl.Intl.pluralLogic(
      seasons,
      locale: localeName,
      other: '$seasons years',
      one: '1 year',
    );
    return 'Failed in $failed of $_temp0';
  }

  @override
  String cardFailRange(String low, String high) {
    return 'Likely range $low–$high';
  }

  @override
  String cardWaterNeeded(int mm) {
    return 'Water needed: $mm mm';
  }

  @override
  String cardNetIncome(String low, String high) {
    return 'Net income: $low to $high per hectare';
  }

  @override
  String get confidenceLabel => 'Confidence';

  @override
  String get confidenceHigh => 'High';

  @override
  String get confidenceMedium => 'Medium';

  @override
  String get confidenceLow => 'Low';

  @override
  String get lowConfidenceNote =>
      'Low confidence. Please check with your Municipal Agriculture Office.';

  @override
  String get onionPriceWarning => 'No cold storage: high price risk';

  @override
  String get holdReasonLabel => 'Why not now';

  @override
  String get holdTip =>
      'Cover the soil with straw (mulch) or let it rest, and get irrigation ready for next season.';

  @override
  String get resultTrackThis => 'Track this crop';

  @override
  String get resultStartOver => 'Answer again';

  @override
  String get myFarmAddPlanting => 'Add planting';

  @override
  String get plantingCrop => 'Crop';

  @override
  String get plantingDate => 'Planting date';

  @override
  String get plantingMethod => 'Method';

  @override
  String get methodDirectSeed => 'Direct seeding';

  @override
  String get methodTransplant => 'Transplanting';

  @override
  String get plantingIrrigation => 'Irrigation';

  @override
  String get plantingSave => 'Save';

  @override
  String get stagePrep => 'Prep';

  @override
  String get stageEstab => 'Establishment';

  @override
  String get stageVeg => 'Vegetative';

  @override
  String get stageRepro => 'Flowering';

  @override
  String get stageMature => 'Maturing';

  @override
  String get stageHarvest => 'Harvest';

  @override
  String get stageFailed => 'Failed';

  @override
  String trackerDay(int day) {
    return 'Day $day';
  }

  @override
  String expectedHarvest(String start, String end) {
    return 'Expected harvest: $start – $end';
  }

  @override
  String get confirmHarvest => 'Confirm harvest';

  @override
  String get waitingForData => 'Waiting for data';

  @override
  String waitingForDataDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days waiting for data',
      one: '1 day waiting for data',
    );
    return '$_temp0';
  }

  @override
  String lastUpdated(String date) {
    return 'Updated $date';
  }

  @override
  String get offlineNote => 'Offline: using saved data';

  @override
  String get demoReplayLabel => 'Replay of a past season';

  @override
  String get alertWaterNow => 'Water now';

  @override
  String get alertWaterNowBody =>
      'The soil is drying out. Irrigate in the next day or two.';

  @override
  String get alertHeatFlowering => 'Heat at flowering';

  @override
  String get alertHeatFloweringBody =>
      'Very hot days during flowering can lower your harvest. Keep the soil moist.';

  @override
  String get alertOnionRot => 'Onion rot risk';

  @override
  String get alertOnionRotBody =>
      'The soil is too wet. Hold off on watering and let the field drain.';

  @override
  String get alertFailed => 'Crop failed';

  @override
  String get alertFailedBody => 'The crop is unlikely to recover this season.';

  @override
  String get alertHarvestReady => 'Ready to harvest';

  @override
  String get alertHarvestReadyBody =>
      'Your crop has reached maturity. Confirm when you harvest.';

  @override
  String get libraryTitle => 'Crop library';

  @override
  String cropDurationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get cropDurationLabel => 'Duration';

  @override
  String get cropSowingWindow => 'Sowing window';

  @override
  String get cropFamily => 'Family';

  @override
  String get cropWaterNeed => 'Water need';

  @override
  String get cropRiskByIrrigation => 'Failed seasons by irrigation';

  @override
  String cropLibrarySubtitle(String town) {
    return 'Five dry-season crops for $town';
  }

  @override
  String cropSowWindowRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String get cropWaterNeedHigh => 'High';

  @override
  String get cropWaterNeedMedium => 'Medium';

  @override
  String get cropWaterNeedLow => 'Low';

  @override
  String get cropWaterNeedRiceNote =>
      'For rice this is a lower bound; real need is higher.';

  @override
  String get cropLegumeNote => 'A legume: it adds nitrogen to the soil.';

  @override
  String get cropSmallMarketNote =>
      'Small local market: check buyers before planting.';

  @override
  String cropFailedOf(int x, int n) {
    return 'Failed $x of $n';
  }

  @override
  String get cropRiskElNinoSeasons => 'El Niño seasons';

  @override
  String get cropRiskOtherSeasons => 'Other seasons';

  @override
  String get cropRiskIrrigationColumn => 'Irrigation';

  @override
  String cropRiskNote(String town) {
    return 'Counted over past dry seasons (2001 to 2025) at one point in $town. This is a guide, not a promise.';
  }

  @override
  String get aboutAdvisory =>
      'Ani gives advice only. Weather is from one point per town, and rice water need is a lower bound. Results were not tested in the field.';

  @override
  String get aboutSources =>
      'Data: NASA POWER, ISRIC SoilGrids, NOAA CPC, PSA.';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionClose => 'Close';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get bundleLoadError => 'Could not load the data for this town.';

  @override
  String homeCropCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count crops in this town\'s data',
      one: '1 crop in this town\'s data',
    );
    return '$_temp0';
  }

  @override
  String get recommendTitle => 'What should I plant?';

  @override
  String get questionLastCropRecent => 'Most recent crop';

  @override
  String get questionLastCropBefore => 'The crop before that';

  @override
  String get questionWaterSourceLabel => 'Where does your water come from?';

  @override
  String get questionIrrigationsLabel =>
      'How many times can you irrigate this dry season?';

  @override
  String get sourceRain => 'Rain only';

  @override
  String get sourcePump => 'Pump or shallow tube well';

  @override
  String get sourceCanal => 'Irrigation canal (NIA or communal)';

  @override
  String get sourceRiver => 'River, creek or pond';

  @override
  String get questionWontHint =>
      'Tap any you will not plant. Leave all empty if none.';

  @override
  String get questionColdStorageLabel => 'Cold storage';

  @override
  String get questionColdStorageHint => 'Matters for onion (Sibuyas) prices.';

  @override
  String questionPrioritiesPicked(int count) {
    return '$count of 3 picked';
  }

  @override
  String cardFailedSeasonsElNino(int failed, int seasons) {
    return 'Failed in $failed of $seasons El Niño years';
  }

  @override
  String cardRank(int rank) {
    return 'No. $rank';
  }

  @override
  String cardConfidence(String level) {
    return 'Confidence: $level';
  }

  @override
  String get cardSmallMarket => 'Small local market: check with the MAO';

  @override
  String resultSubtitle(String town, String water) {
    return '$town · $water';
  }

  @override
  String get resultElNinoMode => 'El Niño year: water and risk count more';

  @override
  String get resultDone => 'Done';

  @override
  String get resultSaved => 'Your answers are saved on this phone.';

  @override
  String holdRemovedCrops(String crops) {
    return 'Ruled out: $crops';
  }

  @override
  String get holdTipLabel => 'What you can do';

  @override
  String get holdGuardWater =>
      'The chance of crop failure is too high for your water supply this El Niño.';

  @override
  String get holdGuardFarmer =>
      'No crop is left after removing the ones you won\'t plant.';

  @override
  String get holdGuardHeat => 'It is too hot at flowering time.';

  @override
  String get holdGuardProfit =>
      'No crop is expected to make a profit this dry season with your water.';

  @override
  String get holdGuardSeason => 'No crop suits the dry season.';

  @override
  String get recommendNoSaved => 'No saved answers yet.';

  @override
  String get homeLastRecommendation => 'See last recommendation';

  @override
  String get homeLastRecommendationTitle => 'Last recommendation';

  @override
  String drynessRankWet(int rank, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      rank,
      locale: localeName,
      other: 'No. $rank wettest',
      one: 'Wettest',
    );
    String _temp1 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years',
      one: '1 year',
    );
    return '$_temp0 of $_temp1';
  }

  @override
  String drynessDValue(String value) {
    return 'D $value';
  }

  @override
  String homeHeatDangerFrom(String category, String value) {
    return 'On $category days (heat index $value°C and up):';
  }

  @override
  String get homeTrackedHint =>
      'Track a planting to see its stage and alerts here.';

  @override
  String get myFarmEmptyTitle => 'No plantings yet';

  @override
  String get myFarmEmptyHint =>
      'Add the crop you planted to follow its stages and get alerts.';

  @override
  String get myFarmGrowing => 'Growing now';

  @override
  String get myFarmPast => 'Past seasons';

  @override
  String plantingPlantedOn(String date) {
    return 'Planted $date';
  }

  @override
  String get plantingDemoTag => 'Demo';

  @override
  String plantingProgress(int percent) {
    return '$percent% of the season';
  }

  @override
  String plantingLastData(String date) {
    return 'Weather data up to $date';
  }

  @override
  String get plantingNoDataYet => 'No weather data yet';

  @override
  String get waitingForDataNote =>
      'NASA POWER publishes a few days late. The tracker moves on when the data arrives.';

  @override
  String get plantingStages => 'Stages';

  @override
  String get stageNotYet => 'Not yet';

  @override
  String get stageNow => 'Now';

  @override
  String plantingReadySince(String date) {
    return 'Ready since $date';
  }

  @override
  String outcomeHarvested(String date) {
    return 'Harvested on $date';
  }

  @override
  String outcomeFailed(String date) {
    return 'Crop failed on $date';
  }

  @override
  String get plantingRemove => 'Remove planting';

  @override
  String get plantingRemoveConfirm =>
      'Remove this planting and its alerts? Past harvest records stay.';

  @override
  String get actionRemove => 'Remove';

  @override
  String get plantingNoAlerts => 'No alerts for this crop.';

  @override
  String get plantingMethodHint =>
      'Only matters for onion: its season is counted from transplanting.';

  @override
  String get plantingIrrigationHint =>
      'Filled in from your last planner answers. Change it if needed.';

  @override
  String get plantingTownLabel => 'Town';

  @override
  String get plantingSaved => 'Planting saved';

  @override
  String get plantingSaveError => 'Could not save the planting.';

  @override
  String get plantingDetailTitle => 'Planting';

  @override
  String get syncUpdating => 'Updating weather…';

  @override
  String get alertsNew => 'New';

  @override
  String alertsTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: 'once',
    );
    return '$_temp0';
  }

  @override
  String get alertsSeeAll => 'See all alerts';

  @override
  String alertsUnseenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new alerts',
      one: '1 new alert',
    );
    return '$_temp0';
  }

  @override
  String get alertWaterStressBody =>
      'The crop is short of water. Irrigate as soon as you can; if you cannot, cover the soil with straw.';

  @override
  String get alertsDemoNote =>
      'Alerts from the replay are not saved and do not notify you.';

  @override
  String get homeOpenMyFarm => 'Open My farm';

  @override
  String get demoTitle => 'Season replay (demo)';

  @override
  String get demoBanner => 'Replay of a past season – not live data';

  @override
  String get demoPickHint =>
      'Pick a past dry season to watch a crop go from planting to harvest in a few taps. Nothing here is saved to your farm.';

  @override
  String demoSeasonTitle(String crop, String town) {
    return '$crop in $town';
  }

  @override
  String demoSeasonSubtitle(String season, String water) {
    return 'Dry season $season · $water';
  }

  @override
  String demoShows(String alerts) {
    return 'Shows: $alerts';
  }

  @override
  String demoDayOf(int day, int total) {
    return 'Day $day of $total';
  }

  @override
  String demoDate(String date) {
    return 'Replay date: $date';
  }

  @override
  String get demoNextDay => 'Next day';

  @override
  String get demoNextWeek => '+7 days';

  @override
  String get demoRunToEnd => 'Run to end';

  @override
  String get demoRestart => 'Start over';

  @override
  String get demoEnded => 'Replay finished';

  @override
  String get demoLoadError => 'Could not load the replay.';

  @override
  String get questionLastCropsFromRecords =>
      'Filled in from your harvest records.';

  @override
  String get outlookTitle => 'Season outlook';

  @override
  String get outlookPastSeasons => 'Past dry seasons';

  @override
  String get outlookLiveTitle => 'Dryness now';

  @override
  String outlookLiveLive(String date) {
    return 'Live from NASA POWER, as of $date';
  }

  @override
  String outlookLiveBundled(String month) {
    return 'Saved reading for $month. Go online for live data.';
  }

  @override
  String get outlookDekadsTitle => 'Last 10-day periods';

  @override
  String outlookDekadRange(int from, int to, String month) {
    return '$from–$to $month';
  }

  @override
  String get outlookDekadPartial => 'so far';

  @override
  String get outlookDekadNoData => 'not enough data';

  @override
  String get outlookChartNote =>
      'Higher means drier. Shaded bands are El Niño dry seasons (Nov–Apr).';

  @override
  String outlookChartYears(int n) {
    return 'Last $n years';
  }

  @override
  String heatAsOf(String date) {
    return 'As of $date';
  }

  @override
  String get heatNoLive => 'No live heat reading yet. Connect once to load it.';

  @override
  String heatDangerDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danger days',
      one: '1 danger day',
    );
    return '$_temp0 in the last week';
  }

  @override
  String get heatRecentTitle => 'Recent days';

  @override
  String get heatDangerToday => 'Danger-level heat. Stay safe.';

  @override
  String get todayConditionsTitle => 'Today\'s conditions';

  @override
  String get condClear => 'Clear skies';

  @override
  String get condPartly => 'Partly cloudy';

  @override
  String get condCloudy => 'Cloudy';

  @override
  String get condRain => 'Rain';

  @override
  String get condHeavyRain => 'Heavy rain';

  @override
  String feelsLike(String v) {
    return 'Feels like $v°';
  }

  @override
  String get humidityLabel => 'Humidity';

  @override
  String get windLabel => 'Wind';

  @override
  String windKmh(String v) {
    return '$v km/h';
  }
}
