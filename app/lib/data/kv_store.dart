import 'package:shared_preferences/shared_preferences.dart';

/// Minimal string key-value store behind the farm store and weather cache:
/// [SharedPreferences] on the device ([PrefsKvStore]), or memory for demo
/// mode and tests ([MemoryKvStore]).
abstract interface class KvStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// [KvStore] on [SharedPreferences].
class PrefsKvStore implements KvStore {
  PrefsKvStore(this.prefs);

  /// Opens the shared instance.
  static Future<PrefsKvStore> open() async => PrefsKvStore(await SharedPreferences.getInstance());

  final SharedPreferences prefs;

  @override
  String? getString(String key) => prefs.getString(key);

  @override
  Future<void> setString(String key, String value) => prefs.setString(key, value);

  @override
  Future<void> remove(String key) => prefs.remove(key);
}

/// In-memory [KvStore] (nothing survives the process).
class MemoryKvStore implements KvStore {
  MemoryKvStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// UTC midnight of [d]'s calendar date (local fields kept as-is).
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// `yyyymmdd` (POWER's date key) for [d].
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// Parses `yyyymmdd` or ISO `yyyy-mm-dd`; null if invalid.
DateTime? parseYmd(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('-', '');
  if (t.length != 8) return null;
  final y = int.tryParse(t.substring(0, 4)), m = int.tryParse(t.substring(4, 6)), d = int.tryParse(t.substring(6, 8));
  if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final r = DateTime.utc(y, m, d);
  return r.month == m ? r : null;
}

/// ISO `yyyy-mm-dd` for [d].
String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
