// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Filipino Pilipino (`fil`).
class AppLocalizationsFil extends AppLocalizations {
  AppLocalizationsFil([String locale = 'fil']) : super(locale);

  @override
  String get appTitle => 'Ani';

  @override
  String get onboardingLanguageTitle => 'Piliin ang iyong wika';

  @override
  String get onboardingLanguageSubtitle =>
      'Maaari mo itong palitan mamaya sa settings.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFilipino => 'Filipino';

  @override
  String get onboardingTownTitle => 'Saan ang inyong bukid?';

  @override
  String get onboardingTownSubtitle =>
      'Gagamitin namin ang datos ng panahon at lupa ng inyong bayan.';

  @override
  String get townGuimba => 'Guimba';

  @override
  String get townMunoz => 'Science City of Muñoz';

  @override
  String get townBongabon => 'Bongabon';

  @override
  String get onboardingContinue => 'Magpatuloy';

  @override
  String get onboardingBack => 'Bumalik';

  @override
  String onboardingStepOf(int step, int total) {
    return 'Hakbang $step sa $total';
  }

  @override
  String get navHome => 'Simula';

  @override
  String get navOutlook => 'Tanaw';

  @override
  String get navCrops => 'Pananim';

  @override
  String get navMyFarm => 'Aking bukid';

  @override
  String get comingSoon => 'Malapit na ang screen na ito.';

  @override
  String get settingsTitle => 'Mga setting';

  @override
  String get settingsChangeTown => 'Palitan ang bayan';

  @override
  String get settingsChangeLanguage => 'Palitan ang wika';

  @override
  String get aboutTitle => 'Tungkol at mga limitasyon';

  @override
  String get aboutLinkSubtitle => 'Ano ang masasabi at hindi masasabi ng Ani';

  @override
  String get aboutLimitsHeading => 'Mga limitasyon';

  @override
  String get aboutLimitPoint =>
      'Isang punto bawat bayan: iisang punto ng panahon at lupa ang gamit para sa buong munisipyo, hindi ang mismong bukid ninyo.';

  @override
  String get aboutLimitAdvisory =>
      'Payo lamang: nagmumungkahi ang Ani, hindi ito ang magpapasya. Kumonsulta sa inyong Municipal Agriculture Office (MAO) bago kumilos.';

  @override
  String get aboutLimitRice =>
      'Ang ipinapakitang pangangailangan ng tubig ng palay ay pinakamababang tantiya: mas marami ang aktwal na nawawala sa bukid dahil sa seepage, percolation at paghahanda ng lupa.';

  @override
  String get aboutLimitTrials =>
      'Hindi pa nasubok sa field trials: galing sa modelo at mga tala ang resulta at hindi pa napatunayan sa mga bukid.';

  @override
  String get aboutLimitHeat =>
      'Payo para sa kaligtasan ng tao lamang ang heat safety; hindi ito ginagamit sa pagpili ng pananim.';

  @override
  String get aboutSourcesHeading => 'Pinagmulan ng datos';

  @override
  String get aboutSourcePower =>
      'NASA POWER: arawang panahon sa bawat bayan, na-sync kapag may internet.';

  @override
  String get aboutSourceSoil =>
      'ISRIC SoilGrids 2.0: katangian ng lupa sa bawat bayan.';

  @override
  String get aboutSourceEnso =>
      'NOAA CPC RONI: tag ng El Niño at La Niña sa bawat tag-init.';

  @override
  String get aboutSourceFao =>
      'FAO-56: gamit ng tubig ng pananim at mga yugto ng paglaki.';

  @override
  String get aboutSourcePsa =>
      'PSA OpenSTAT at PSA costs and returns: nakaraang ani at presyo.';

  @override
  String get aboutSourcePagasa =>
      'PAGASA: mga kategorya ng heat index para sa payo sa init.';

  @override
  String get aboutSourceMao =>
      'MAO referral: kapag mababa ang tiwala sa resulta, itinuturo kayo ng Ani sa inyong Municipal Agriculture Office.';

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
  String get homeCta => 'Ano ang dapat kong itanim?';

  @override
  String get homeOutlookTitle => 'Tanaw sa tag-araw';

  @override
  String get homeTrackedTitle => 'Ang inyong tanim';

  @override
  String get homeTrackedEmpty => 'Wala pang binabantayang tanim.';

  @override
  String get alertsTitle => 'Mga babala';

  @override
  String get alertsEmpty => 'Walang babala sa ngayon.';

  @override
  String get ensoElNino => 'El Niño';

  @override
  String get ensoLaNina => 'La Niña';

  @override
  String get ensoNeutral => 'Neutral';

  @override
  String ensoStrength(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      'weak': 'Mahina',
      'moderate': 'Katamtaman',
      'strong': 'Malakas',
      'veryStrong': 'Napakalakas',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get drynessTitle => 'Pagkatuyo';

  @override
  String drynessRank(int rank, int n) {
    return 'Ika-$rank sa pinakatuyo sa $n na taon';
  }

  @override
  String get drynessChartTitle => 'Buwanang sukat ng pagkatuyo';

  @override
  String get drynessChartElNino => 'Mga panahon ng El Niño';

  @override
  String get heatSafetyTitle => 'Kaligtasan sa init';

  @override
  String heatIndexValue(String value) {
    return 'Heat index $value°C';
  }

  @override
  String get heatCaution => 'Mag-ingat';

  @override
  String get heatExtremeCaution => 'Labis na mag-ingat';

  @override
  String get heatDanger => 'Mapanganib';

  @override
  String get heatExtremeDanger => 'Lubhang mapanganib';

  @override
  String get heatSafetyNote =>
      'Para lang sa kaligtasan ng tao. Hindi ginagamit sa pagpili ng pananim.';

  @override
  String questionStepOf(int step, int total) {
    return 'Tanong $step sa $total';
  }

  @override
  String get questionTownTitle => 'Saang bayan ang inyong bukid?';

  @override
  String get questionLastCropsTitle =>
      'Ano ang huling dalawang itinanim ninyo?';

  @override
  String get questionLastCropsHint =>
      'Ang pinakahuli muna. Piliin ang Wala kung walang tanim.';

  @override
  String get questionWaterTitle => 'Gaano karaming patubig ang kaya ninyo?';

  @override
  String get waterRainfed => 'Ulan lang (walang patubig)';

  @override
  String get waterLimited2 => 'Mga 2 patubig';

  @override
  String get waterLimited4 => 'Mga 4 na patubig';

  @override
  String get waterFull => 'Patubig kung kailangan';

  @override
  String get questionWontTitle => 'May pananim bang ayaw ninyong itanim?';

  @override
  String get questionColdStorage => 'May magagamit akong cold storage';

  @override
  String get questionPrioritiesTitle => 'Ano ang pinakamahalaga sa inyo?';

  @override
  String get questionPrioritiesHint =>
      'Pindutin ang nangungunang 3, ang pinakamahalaga muna.';

  @override
  String get priorityIncome => 'Kita';

  @override
  String get priorityRisk => 'Mababang panganib';

  @override
  String get priorityWater => 'Tipid sa tubig';

  @override
  String get prioritySoil => 'Kalusugan ng lupa';

  @override
  String get priorityPest => 'Mas kaunting peste';

  @override
  String get answerNone => 'Wala';

  @override
  String get questionSeeResult => 'Tingnan ang payo';

  @override
  String get resultTitle => 'Mga mungkahing pananim';

  @override
  String cardFailedSeasons(int failed, int seasons) {
    return 'Nasira sa $failed sa $seasons na taon';
  }

  @override
  String cardFailRange(String low, String high) {
    return 'Maaaring $low–$high';
  }

  @override
  String cardWaterNeeded(int mm) {
    return 'Kailangang tubig: $mm mm';
  }

  @override
  String cardNetIncome(String low, String high) {
    return 'Netong kita: $low hanggang $high bawat ektarya';
  }

  @override
  String get confidenceLabel => 'Katiyakan';

  @override
  String get confidenceHigh => 'Mataas';

  @override
  String get confidenceMedium => 'Katamtaman';

  @override
  String get confidenceLow => 'Mababa';

  @override
  String get lowConfidenceNote =>
      'Mababa ang katiyakan. Makipag-usap muna sa inyong Municipal Agriculture Office.';

  @override
  String get onionPriceWarning =>
      'Walang cold storage: mataas ang panganib sa presyo';

  @override
  String get holdReasonLabel => 'Bakit hindi muna';

  @override
  String get holdTip =>
      'Takpan ng dayami (mulch) o iwanang pahinga ang lupa; ihanda ang patubig para sa susunod.';

  @override
  String get resultTrackThis => 'Bantayan ang tanim na ito';

  @override
  String get resultStartOver => 'Sumagot muli';

  @override
  String get myFarmAddPlanting => 'Magdagdag ng tanim';

  @override
  String get plantingCrop => 'Pananim';

  @override
  String get plantingDate => 'Petsa ng pagtatanim';

  @override
  String get plantingMethod => 'Paraan';

  @override
  String get methodDirectSeed => 'Direktang pagtatanim';

  @override
  String get methodTransplant => 'Paglilipat-tanim';

  @override
  String get plantingIrrigation => 'Patubig';

  @override
  String get plantingSave => 'I-save';

  @override
  String get stagePrep => 'Paghahanda';

  @override
  String get stageEstab => 'Pagtubo';

  @override
  String get stageVeg => 'Paglaki';

  @override
  String get stageRepro => 'Pamumulaklak';

  @override
  String get stageMature => 'Paghinog';

  @override
  String get stageHarvest => 'Anihan';

  @override
  String get stageFailed => 'Nasira';

  @override
  String trackerDay(int day) {
    return 'Ika-$day na araw';
  }

  @override
  String expectedHarvest(String start, String end) {
    return 'Inaasahang ani: $start – $end';
  }

  @override
  String get confirmHarvest => 'Kumpirmahin ang ani';

  @override
  String get waitingForData => 'Hinihintay ang datos';

  @override
  String waitingForDataDays(int count) {
    return '$count araw na hinihintay ang datos';
  }

  @override
  String lastUpdated(String date) {
    return 'Na-update $date';
  }

  @override
  String get offlineNote => 'Offline: gamit ang naka-save na datos';

  @override
  String get demoReplayLabel => 'Replay ng nakaraang panahon';

  @override
  String get alertWaterNow => 'Magpatubig na';

  @override
  String get alertWaterNowBody =>
      'Natutuyo na ang lupa. Magpatubig sa loob ng isa o dalawang araw.';

  @override
  String get alertHeatFlowering => 'Init sa pamumulaklak';

  @override
  String get alertHeatFloweringBody =>
      'Ang sobrang init habang namumulaklak ay maaaring magpababa ng ani. Panatilihing basa ang lupa.';

  @override
  String get alertOnionRot => 'Panganib ng pagkabulok ng sibuyas';

  @override
  String get alertOnionRotBody =>
      'Sobrang basa ang lupa. Itigil muna ang patubig at padaluyin ang tubig.';

  @override
  String get alertFailed => 'Nasira ang tanim';

  @override
  String get alertFailedBody => 'Malabong makabawi ang tanim ngayong panahon.';

  @override
  String get alertHarvestReady => 'Handa nang anihin';

  @override
  String get alertHarvestReadyBody =>
      'Hinog na ang inyong tanim. Kumpirmahin kapag umani na kayo.';

  @override
  String get libraryTitle => 'Mga pananim';

  @override
  String cropDurationDays(int days) {
    return '$days araw';
  }

  @override
  String get cropDurationLabel => 'Haba ng panahon';

  @override
  String get cropSowingWindow => 'Panahon ng pagtatanim';

  @override
  String get cropFamily => 'Pamilya';

  @override
  String get cropWaterNeed => 'Kailangang tubig';

  @override
  String get cropRiskByIrrigation => 'Nasirang panahon ayon sa patubig';

  @override
  String cropLibrarySubtitle(String town) {
    return 'Limang pananim sa tag-araw para sa $town';
  }

  @override
  String cropSowWindowRange(String start, String end) {
    return '$start hanggang $end';
  }

  @override
  String get cropWaterNeedHigh => 'Mataas';

  @override
  String get cropWaterNeedMedium => 'Katamtaman';

  @override
  String get cropWaterNeedLow => 'Mababa';

  @override
  String get cropWaterNeedRiceNote =>
      'Pinakamababang tantya ito para sa palay; mas mataas ang totoong kailangan.';

  @override
  String get cropLegumeNote =>
      'Legume ito, tulad ng munggo: nagdaragdag ito ng nitroheno sa lupa.';

  @override
  String get cropSmallMarketNote =>
      'Maliit ang lokal na bilihan: alamin muna ang mga bumibili bago magtanim.';

  @override
  String cropFailedOf(int x, int n) {
    return 'Nasira ang $x sa $n';
  }

  @override
  String get cropRiskElNinoSeasons => 'Mga panahong El Niño';

  @override
  String get cropRiskOtherSeasons => 'Ibang mga panahon';

  @override
  String get cropRiskIrrigationColumn => 'Patubig';

  @override
  String cropRiskNote(String town) {
    return 'Binilang sa mga nakaraang tag-araw (2001 hanggang 2025) sa isang punto sa $town. Gabay ito, hindi pangako.';
  }

  @override
  String get aboutAdvisory =>
      'Payo lang ang Ani. Ang panahon ay mula sa iisang punto bawat bayan, at pinakamababang tantya ang tubig para sa palay. Hindi pa ito nasubok sa bukid.';

  @override
  String get aboutSources =>
      'Datos: NASA POWER, ISRIC SoilGrids, NOAA CPC, PSA.';

  @override
  String get actionRetry => 'Subukan muli';

  @override
  String get actionClose => 'Isara';

  @override
  String get actionCancel => 'Kanselahin';

  @override
  String get bundleLoadError => 'Hindi ma-load ang datos para sa bayang ito.';

  @override
  String homeCropCount(int count) {
    return '$count pananim sa datos ng bayang ito';
  }

  @override
  String get recommendTitle => 'Ano ang dapat kong itanim?';

  @override
  String get questionLastCropRecent => 'Pinakahuling tanim';

  @override
  String get questionLastCropBefore => 'Ang tanim bago noon';

  @override
  String get questionWaterSourceLabel => 'Saan galing ang inyong tubig?';

  @override
  String get questionIrrigationsLabel =>
      'Ilang beses kayong makapagpapatubig ngayong tag-araw?';

  @override
  String get sourceRain => 'Ulan lang';

  @override
  String get sourcePump => 'Bomba o mababaw na balon';

  @override
  String get sourceCanal => 'Kanal ng patubig (NIA o komunal)';

  @override
  String get sourceRiver => 'Ilog, sapa o lawa';

  @override
  String get questionWontHint =>
      'Pindutin ang ayaw ninyong itanim. Iwanang walang pili kung wala.';

  @override
  String get questionColdStorageLabel => 'Cold storage';

  @override
  String get questionColdStorageHint => 'Mahalaga sa presyo ng sibuyas.';

  @override
  String questionPrioritiesPicked(int count) {
    return '$count sa 3 ang napili';
  }

  @override
  String cardFailedSeasonsElNino(int failed, int seasons) {
    return 'Nasira sa $failed sa $seasons na El Niño na taon';
  }

  @override
  String cardRank(int rank) {
    return 'Ika-$rank';
  }

  @override
  String cardConfidence(String level) {
    return 'Katiyakan: $level';
  }

  @override
  String get cardSmallMarket =>
      'Maliit ang lokal na pamilihan: kumonsulta sa MAO';

  @override
  String resultSubtitle(String town, String water) {
    return '$town · $water';
  }

  @override
  String get resultElNinoMode =>
      'Taon ng El Niño: mas mabigat ang tubig at panganib';

  @override
  String get resultDone => 'Tapos na';

  @override
  String get resultSaved => 'Naka-save sa teleponong ito ang inyong mga sagot.';

  @override
  String holdRemovedCrops(String crops) {
    return 'Tinanggal: $crops';
  }

  @override
  String get holdTipLabel => 'Ano ang magagawa';

  @override
  String get holdGuardWater =>
      'Masyadong mataas ang tsansang masira sa inyong patubig ngayong El Niño.';

  @override
  String get holdGuardFarmer =>
      'Wala nang natirang pananim matapos alisin ang ayaw ninyong itanim.';

  @override
  String get holdGuardHeat => 'Masyadong mainit sa panahon ng pamumulaklak.';

  @override
  String get holdGuardProfit =>
      'Walang pananim na inaasahang kikita ngayong tag-araw sa inyong patubig.';

  @override
  String get holdGuardSeason => 'Walang pananim na angkop sa tag-araw.';

  @override
  String get recommendNoSaved => 'Wala pang naka-save na sagot.';

  @override
  String get homeLastRecommendation => 'Tingnan ang huling payo';

  @override
  String get homeLastRecommendationTitle => 'Huling payo';

  @override
  String drynessRankWet(int rank, int n) {
    return 'Ika-$rank sa pinakabasa sa $n na taon';
  }

  @override
  String drynessDValue(String value) {
    return 'D $value';
  }

  @override
  String homeHeatDangerFrom(String category, String value) {
    return 'Sa mga araw na $category (heat index $value°C pataas):';
  }

  @override
  String get homeTrackedHint =>
      'Magtala ng tanim para makita rito ang yugto at mga babala nito.';

  @override
  String get myFarmEmptyTitle => 'Wala pang nakatalang tanim';

  @override
  String get myFarmEmptyHint =>
      'Itala ang inyong itinanim para masundan ang yugto nito at makatanggap ng babala.';

  @override
  String get myFarmGrowing => 'Kasalukuyang tanim';

  @override
  String get myFarmPast => 'Mga nakaraang taniman';

  @override
  String plantingPlantedOn(String date) {
    return 'Itinanim $date';
  }

  @override
  String get plantingDemoTag => 'Demo';

  @override
  String plantingProgress(int percent) {
    return '$percent% ng panahon';
  }

  @override
  String plantingLastData(String date) {
    return 'May datos ng panahon hanggang $date';
  }

  @override
  String get plantingNoDataYet => 'Wala pang datos ng panahon';

  @override
  String get waitingForDataNote =>
      'Ilang araw na huli ang datos ng NASA POWER. Uusad ang tala kapag dumating na ito.';

  @override
  String get plantingStages => 'Mga yugto';

  @override
  String get stageNotYet => 'Hindi pa';

  @override
  String get stageNow => 'Ngayon';

  @override
  String plantingReadySince(String date) {
    return 'Handa na mula $date';
  }

  @override
  String outcomeHarvested(String date) {
    return 'Inani noong $date';
  }

  @override
  String outcomeFailed(String date) {
    return 'Nasira ang tanim noong $date';
  }

  @override
  String get plantingRemove => 'Alisin ang tanim';

  @override
  String get plantingRemoveConfirm =>
      'Alisin ang tanim na ito at ang mga babala nito? Mananatili ang tala ng nakaraang ani.';

  @override
  String get actionRemove => 'Alisin';

  @override
  String get plantingNoAlerts => 'Walang babala para sa tanim na ito.';

  @override
  String get plantingMethodHint =>
      'Sa sibuyas lang ito mahalaga: binibilang ang panahon nito mula sa paglilipat-tanim.';

  @override
  String get plantingIrrigationHint =>
      'Mula sa huli ninyong sagot sa payo. Palitan kung kailangan.';

  @override
  String get plantingTownLabel => 'Bayan';

  @override
  String get plantingSaved => 'Naitala ang tanim';

  @override
  String get plantingSaveError => 'Hindi ma-save ang tanim.';

  @override
  String get plantingDetailTitle => 'Tanim';

  @override
  String get syncUpdating => 'Ina-update ang panahon…';

  @override
  String get alertsNew => 'Bago';

  @override
  String alertsTimes(int count) {
    return '$count beses';
  }

  @override
  String get alertsSeeAll => 'Tingnan lahat ng babala';

  @override
  String alertsUnseenCount(int count) {
    return '$count bagong babala';
  }

  @override
  String get alertWaterStressBody =>
      'Kulang sa tubig ang tanim. Magpatubig agad kung kaya; kung hindi, takpan ng dayami ang lupa.';

  @override
  String get alertsDemoNote =>
      'Hindi naka-save at hindi magpapadala ng abiso ang mga babala sa replay.';

  @override
  String get homeOpenMyFarm => 'Buksan ang Aking bukid';

  @override
  String get demoTitle => 'Replay ng panahon (demo)';

  @override
  String get demoBanner => 'Replay ng nakaraang panahon – hindi live na datos';

  @override
  String get demoPickHint =>
      'Pumili ng nakaraang tag-araw para makita ang tanim mula pagtatanim hanggang anihan. Walang mase-save sa inyong bukid.';

  @override
  String demoSeasonTitle(String crop, String town) {
    return '$crop sa $town';
  }

  @override
  String demoSeasonSubtitle(String season, String water) {
    return 'Tag-araw $season · $water';
  }

  @override
  String demoShows(String alerts) {
    return 'Makikita: $alerts';
  }

  @override
  String demoDayOf(int day, int total) {
    return 'Araw $day sa $total';
  }

  @override
  String demoDate(String date) {
    return 'Petsa sa replay: $date';
  }

  @override
  String get demoNextDay => 'Susunod na araw';

  @override
  String get demoNextWeek => '+7 araw';

  @override
  String get demoRunToEnd => 'Hanggang dulo';

  @override
  String get demoRestart => 'Ulitin';

  @override
  String get demoEnded => 'Tapos na ang replay';

  @override
  String get demoLoadError => 'Hindi ma-load ang replay.';

  @override
  String get questionLastCropsFromRecords => 'Mula sa tala ng inyong ani.';

  @override
  String get outlookTitle => 'Tanaw sa panahon';

  @override
  String get outlookPastSeasons => 'Mga nakaraang tag-araw';

  @override
  String get outlookLiveTitle => 'Tuyot ngayon';

  @override
  String outlookLiveLive(String date) {
    return 'Live mula sa NASA POWER, hanggang $date';
  }

  @override
  String outlookLiveBundled(String month) {
    return 'Naka-save na basa para sa $month. Mag-online para sa live na datos.';
  }

  @override
  String get outlookDekadsTitle => 'Mga huling 10-araw na yugto';

  @override
  String outlookDekadRange(int from, int to, String month) {
    return '$from–$to $month';
  }

  @override
  String get outlookDekadPartial => 'sa ngayon';

  @override
  String get outlookDekadNoData => 'kulang ang datos';

  @override
  String get outlookChartNote =>
      'Mas mataas, mas tuyot. Ang may kulay ay mga tag-araw na El Niño (Nob–Abr).';

  @override
  String outlookChartYears(int n) {
    return 'Huling $n taon';
  }

  @override
  String heatAsOf(String date) {
    return 'Hanggang $date';
  }

  @override
  String get heatNoLive =>
      'Wala pang live na init. Mag-online nang isang beses para ma-load.';

  @override
  String heatDangerDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count araw',
      one: '1 araw',
    );
    return '$_temp0 na delikado nitong nakaraang linggo';
  }

  @override
  String get heatRecentTitle => 'Mga nakaraang araw';

  @override
  String get heatDangerToday => 'Delikadong init. Mag-ingat.';

  @override
  String get todayConditionsTitle => 'Kalagayan ngayon';

  @override
  String get condClear => 'Maaliwalas';

  @override
  String get condPartly => 'Bahagyang maulap';

  @override
  String get condCloudy => 'Maulap';

  @override
  String get condRain => 'Umuulan';

  @override
  String get condHeavyRain => 'Malakas na ulan';

  @override
  String feelsLike(String v) {
    return 'Pakiramdam: $v°';
  }

  @override
  String get humidityLabel => 'Halumigmig';

  @override
  String get windLabel => 'Hangin';

  @override
  String windKmh(String v) {
    return '$v km/h';
  }
}
