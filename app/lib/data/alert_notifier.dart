/// Local notifications for new in-season alerts (docs/PLAN.md Phase 4.5).
///
/// The app talks to an [AlertNotifier] only. [AlertNotifier.platform] picks
/// [LocalAlertNotifier] (flutter_local_notifications) on Android / iOS and
/// [NoopAlertNotifier] everywhere else (web, desktop). Tests inject their
/// own. Callers pass only the farmer's real alerts: demo replays never reach
/// a notifier.
///
/// The plugin is touched lazily (first [AlertNotifier.requestPermission] or
/// [AlertNotifier.show]), never at construction, so creating the default
/// notifier is safe in tests and on cold start. Permission is never
/// requested on launch: the app asks once, after the farmer saves their
/// first planting (the moment notifications start to matter).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// One notification to show.
class AlertNotice {
  const AlertNotice({required this.id, required this.title, required this.body});

  /// Stable id (re-showing the same id replaces the notification).
  final int id;
  final String title;
  final String body;
}

/// Shows local notifications for alerts.
abstract interface class AlertNotifier {
  /// The notifier for the current platform (no-op off Android / iOS).
  factory AlertNotifier.platform() {
    if (kIsWeb) return const NoopAlertNotifier();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => LocalAlertNotifier(),
      _ => const NoopAlertNotifier(),
    };
  }

  /// Asks the OS for permission to notify; returns whether granted (null if
  /// unknown). Never throws.
  Future<bool?> requestPermission();

  /// Shows [notices]. Never throws.
  Future<void> show(List<AlertNotice> notices);
}

/// Does nothing (web, desktop, tests).
class NoopAlertNotifier implements AlertNotifier {
  const NoopAlertNotifier();

  @override
  Future<bool?> requestPermission() async => null;

  @override
  Future<void> show(List<AlertNotice> notices) async {}
}

/// flutter_local_notifications on Android and iOS.
class LocalAlertNotifier implements AlertNotifier {
  LocalAlertNotifier({FlutterLocalNotificationsPlugin? plugin}) : _pluginOverride = plugin;

  static const channelId = 'ani_alerts';
  static const channelName = 'Crop alerts';

  final FlutterLocalNotificationsPlugin? _pluginOverride;
  FlutterLocalNotificationsPlugin? _plugin;
  Future<bool>? _init;

  Future<bool> _ready() => _init ??= () async {
        try {
          final p = _plugin = _pluginOverride ?? FlutterLocalNotificationsPlugin();
          await p.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              // Ask later, politely (see requestPermission), not at init.
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          );
          return true;
        } catch (e) {
          debugPrint('notifications unavailable: $e');
          return false;
        }
      }();

  @override
  Future<bool?> requestPermission() async {
    if (!await _ready()) return false;
    try {
      final p = _plugin!;
      final android = p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission();
      final ios = p.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('notification permission failed: $e');
    }
    return null;
  }

  @override
  Future<void> show(List<AlertNotice> notices) async {
    if (notices.isEmpty || !await _ready()) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    for (final n in notices) {
      try {
        await _plugin!.show(id: n.id, title: n.title, body: n.body, notificationDetails: details);
      } catch (e) {
        debugPrint('notification failed: $e');
      }
    }
  }
}

/// A 31-bit notification id derived from a string (FNV-1a; stable across runs,
/// unlike [String.hashCode] on the web).
int noticeIdFor(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}
