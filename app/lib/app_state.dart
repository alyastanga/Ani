import 'package:flutter/widgets.dart';

import 'core/planner.dart';
import 'data/alert_notifier.dart';
import 'data/bundle.dart';
import 'data/demo_seasons.dart';
import 'data/live_outlook.dart';
import 'data/planner_profile.dart';
import 'data/settings_store.dart';
import 'data/tracker_service.dart';
import 'features/alerts/alert_labels.dart';
import 'l10n/app_localizations.dart';

/// App-wide state: language, town, onboarding flag, the town's bundle and the
/// last planner answers.
class AppState extends ChangeNotifier {
  AppState({
    Future<SettingsStore> Function()? openStore,
    BundleLoader? loader,
    this.assets,
    Future<TrackerService> Function(Future<AniBundle> Function(Town town) bundleFor)? openTracker,
    AlertNotifier? notifier,
    Future<List<DemoSeason>> Function()? loadDemoSeasons,
  })  : _openStore = openStore ?? SettingsStore.load,
        _loader = loader ?? BundleLoader.instance,
        _openTracker = openTracker ?? ((bundleFor) => TrackerService.open(bundleFor: bundleFor)),
        notifier = notifier ?? AlertNotifier.platform(),
        _loadDemoSeasons = loadDemoSeasons ?? (() => DemoSeasons.load(bundle: assets));

  final Future<SettingsStore> Function() _openStore;
  final Future<TrackerService> Function(Future<AniBundle> Function(Town town) bundleFor) _openTracker;
  final Future<List<DemoSeason>> Function() _loadDemoSeasons;
  Future<TrackerService>? _tracker;
  TrackerService? _trackerService;
  Future<List<DemoSeason>>? _demoSeasons;

  /// Local notifications for new real alerts (no-op on web / in tests).
  final AlertNotifier notifier;

  /// The crop tracker (plantings, POWER sync, alerts), opened on first use.
  /// Use [refreshTracker] to sync and replay (app start / resume, My farm).
  Future<TrackerService> tracker() => _tracker ??= _openTracker(bundleFor).then((t) {
        _trackerService = t;
        notifyListeners();
        return t;
      }, onError: (Object e, StackTrace st) {
        _tracker = null;
        Error.throwWithStackTrace(e, st);
      });

  /// The tracker once [tracker] has opened it, else null.
  TrackerService? get trackerService => _trackerService;

  Future<TrackerRefresh?>? _refreshing;
  TrackerRefresh? _lastRefresh;
  DateTime? _lastRefreshAt;

  bool _trackerLoaded = false;

  /// True once a [refreshTracker] has finished (successfully or not), so
  /// the tracker's views are meaningful.
  bool get trackerLoaded => _trackerLoaded;

  /// True while [refreshTracker] runs.
  bool get trackerRefreshing => _refreshing != null;

  /// Result of the last finished [refreshTracker], or null.
  TrackerRefresh? get lastTrackerRefresh => _lastRefresh;

  /// When the last [refreshTracker] finished.
  DateTime? get lastTrackerRefreshAt => _lastRefreshAt;

  /// Opens the tracker, syncs POWER (unless [sync] is false), replays every
  /// open planting and shows notifications for the new real alerts. Calls
  /// that overlap share one run. Never throws; returns null on failure.
  Future<TrackerRefresh?> refreshTracker({bool sync = true}) {
    final running = _refreshing;
    if (running != null) return running;
    final f = _refreshing = _doRefresh(sync: sync);
    notifyListeners();
    return f;
  }

  Future<TrackerRefresh?> _doRefresh({required bool sync}) async {
    TrackerRefresh? r;
    try {
      final t = await tracker();
      r = await t.refresh(sync: sync);
      _lastRefresh = r;
      _lastRefreshAt = DateTime.now();
      final notices = noticesFor(_notificationStrings(), r.newAlerts.where((a) => !a.isDemo));
      if (notices.isNotEmpty) await notifier.show(notices);
    } catch (e) {
      debugPrint('tracker refresh failed: $e');
    }
    await refreshLive(sync: sync);
    _refreshing = null;
    _trackerLoaded = true;
    notifyListeners();
    return r;
  }

  LiveOutlook? _live;
  Future<LiveOutlook?>? _liveRefreshing;

  /// The live dekadal D and heat index for the current town from the POWER
  /// cache, or null until [refreshLive] has produced one for this town.
  LiveOutlook? get live => _live != null && _live!.town == _town ? _live : null;

  /// Syncs POWER for the current town (unless [sync] is false, or offline:
  /// the cache is used as it is), then recomputes [live]. Calls that overlap
  /// share one run. Never throws; returns null when there is no town / bundle
  /// or the tracker cannot open.
  Future<LiveOutlook?> refreshLive({bool sync = true}) {
    final running = _liveRefreshing;
    if (running != null) return running;
    final f = _liveRefreshing = _doRefreshLive(sync: sync).whenComplete(() => _liveRefreshing = null);
    return f;
  }

  Future<LiveOutlook?> _doRefreshLive({required bool sync}) async {
    try {
      final town = _town, bundle = _bundle;
      if (town == null || bundle == null) return null;
      final t = await tracker();
      final today = t.today;
      if (sync) {
        await t.weather.sync(town, bundle,
            from: today.subtract(const Duration(days: LiveOutlook.lookbackDays)), today: today);
      }
      final live = LiveOutlook.compute(town: town, bundle: bundle, days: t.weather.daysFor(town), today: today);
      if (town == _town) {
        _live = live;
        notifyListeners();
      }
      return live;
    } catch (e) {
      debugPrint('live outlook failed: $e');
      return null;
    }
  }

  AppLocalizations _notificationStrings() {
    var code = _localeCode;
    code ??= WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'fil' ? 'fil' : 'en';
    return lookupAppLocalizations(Locale(code));
  }

  /// Asks for notification permission once (after the first real planting
  /// is saved, not on launch). Never throws.
  Future<void> requestNotificationPermissionOnce() async {
    final store = _store;
    if (store == null || store.notificationsAsked) return;
    await store.setNotificationsAsked();
    try {
      await notifier.requestPermission();
    } catch (_) {}
  }

  /// The bundled demo seasons (loaded once).
  Future<List<DemoSeason>> demoSeasons() => _demoSeasons ??= _loadDemoSeasons().catchError((Object e) {
        _demoSeasons = null;
        Error.throwWithStackTrace(e, StackTrace.current);
      });

  /// Starts a replay of [season] on its own in-memory store (never the
  /// farmer's records).
  Future<DemoReplay> startDemo(DemoSeason season) async {
    final b = await bundleFor(season.town);
    return DemoReplay(season, b);
  }

  final BundleLoader _loader;

  /// Asset bundle to read town JSON from (default rootBundle).
  final AssetBundle? assets;

  SettingsStore? _store;
  Future<void>? _initFuture;
  int _loadToken = 0;

  bool _initialized = false;
  String? _localeCode;
  Town? _town;
  bool _onboardingComplete = false;
  AniBundle? _bundle;
  Object? _bundleError;
  bool _bundleLoading = false;
  SavedPlannerProfile? _plannerProfile;

  /// True once saved settings have been read.
  bool get initialized => _initialized;

  /// Selected language code, or null to follow the device.
  String? get localeCode => _localeCode;
  Locale? get locale => _localeCode == null ? null : Locale(_localeCode!);

  Town? get town => _town;
  bool get onboardingComplete => _onboardingComplete;

  /// The loaded bundle for [town], if any.
  AniBundle? get bundle => _bundle;
  Object? get bundleError => _bundleError;
  bool get bundleLoading => _bundleLoading;

  /// The last answers given to the planner (saved on the device), or null.
  SavedPlannerProfile? get plannerProfile => _plannerProfile;

  /// True if a recommendation can be reopened with [lastRecommendation].
  bool get hasRecommendation => _plannerProfile != null;

  /// Reads saved settings and, if a town is saved, loads its bundle.
  /// Safe to call more than once.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    final store = _store = await _openStore();
    _localeCode = store.locale;
    _town = store.town;
    _onboardingComplete = store.onboardingComplete;
    _plannerProfile = store.plannerProfile;
    _initialized = true;
    notifyListeners();
    if (_town != null) await _loadBundle(_town!);
  }

  /// Switches the app language and saves it.
  Future<void> setLocale(String code) async {
    if (code == _localeCode) return;
    await _store?.setLocale(code);
    _localeCode = code;
    notifyListeners();
  }

  /// Saves [town], marks onboarding done and loads the bundle.
  Future<void> completeOnboarding(Town town) async {
    await _store?.setTown(town);
    await _store?.setOnboardingComplete(true);
    _onboardingComplete = true;
    await _switchTown(town);
  }

  /// Changes the town (from settings) and reloads the bundle.
  Future<void> setTown(Town town) async {
    if (town == _town && _bundle != null) return;
    await _store?.setTown(town);
    await _switchTown(town);
  }

  /// Saves the planner answers locally (replacing the previous ones).
  Future<void> savePlannerProfile(SavedPlannerProfile profile) async {
    await _store?.setPlannerProfile(profile);
    _plannerProfile = profile;
    notifyListeners();
  }

  /// The bundle for [town]: the loaded one if it is the current town, else
  /// loaded (and cached) without changing the app's town.
  Future<AniBundle> bundleFor(Town town) {
    final b = _bundle;
    if (b != null && town == _town) return Future.value(b);
    return _loader.load(town, bundle: assets);
  }

  /// Re-plans the saved answers on their town's bundle; null if nothing is
  /// saved. The plan is deterministic, so this reproduces the last result
  /// for the same bundle.
  Future<({SavedPlannerProfile saved, PlanResult result})?> lastRecommendation() async {
    final saved = _plannerProfile;
    final town = saved?.town;
    if (saved == null || town == null) return null;
    final b = await bundleFor(town);
    return (saved: saved, result: planWithBundle(saved.profile, b));
  }

  /// Retries loading the current town's bundle after an error.
  Future<void> retryBundle() async {
    if (_town != null) await _loadBundle(_town!);
  }

  // The previous bundle stays visible until the new one arrives.
  Future<void> _switchTown(Town town) async {
    _town = town;
    await _loadBundle(town);
    refreshLive(sync: false).ignore(); // cache only; the Outlook tab syncs
  }

  Future<void> _loadBundle(Town town) async {
    final token = ++_loadToken;
    _bundleLoading = true;
    _bundleError = null;
    notifyListeners();
    try {
      final b = await _loader.load(town, bundle: assets);
      if (token != _loadToken) return;
      _bundle = b;
    } catch (e) {
      if (token != _loadToken) return;
      _bundle = null;
      _bundleError = e;
    }
    _bundleLoading = false;
    notifyListeners();
  }
}

/// Exposes [AppState] to the widget tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.notifier!;
  }
}
