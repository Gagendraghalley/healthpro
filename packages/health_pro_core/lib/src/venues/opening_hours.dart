/// A time a venue opens or closes: minutes after midnight (24:00 is 1440).
class OpenPeriod {
  final int open;
  final int close;

  const OpenPeriod(this.open, this.close);

  bool contains(int minute) => minute >= open && minute < close;

  /// '06:00', as the database keeps it.
  static String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  static int? parse(String? value) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value ?? '');
    if (m == null) return null;
    final minutes = int.parse(m[1]!) * 60 + int.parse(m[2]!);
    return minutes <= 1440 ? minutes : null;
  }

  /// '6 am', '6:30 am', '12 pm', 'midnight'.
  static String label(int minutes) {
    if (minutes == 0 || minutes == 1440) return 'midnight';
    final h = minutes ~/ 60, m = minutes % 60;
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'} ${h < 12 ? 'am' : 'pm'}';
  }

  /// '6–10 am', '6 am–9 pm'.
  String get text {
    final a = label(open), b = label(close);
    final sameHalf = open < 720 == close < 720 && close != 1440 && open != 0;
    return sameHalf ? '${a.replaceAll(RegExp(r' [ap]m$'), '')}–$b' : '$a–$b';
  }

  @override
  bool operator ==(Object other) => other is OpenPeriod && other.open == open && other.close == close;

  @override
  int get hashCode => Object.hash(open, close);
}

/// Whether a venue is open at a moment, and the next change.
class OpenNow {
  final bool open;

  /// 'Open now · until 9 pm', 'Closed · opens 4 pm', 'Closed today'.
  final String label;

  const OpenNow(this.open, this.label);
}

/// When a venue is open, day by day (Monday 1 to Sunday 7): one or two
/// periods, none for a day it's closed; a day it hasn't said isn't there.
class OpeningHours {
  final Map<int, List<OpenPeriod>> days;

  const OpeningHours(this.days);

  static const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const fullNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  bool get isEmpty => days.isEmpty;

  /// What a new venue starts with in the form: Monday to Saturday 6 am to
  /// 9 pm, closed on Sunday.
  static const usual = OpeningHours({
    1: [OpenPeriod(360, 1260)],
    2: [OpenPeriod(360, 1260)],
    3: [OpenPeriod(360, 1260)],
    4: [OpenPeriod(360, 1260)],
    5: [OpenPeriod(360, 1260)],
    6: [OpenPeriod(360, 1260)],
    7: [],
  });

  /// venues.opening_hours: `{"mon": [["06:00", "21:00"]], "sun": []}`.
  static OpeningHours? fromJson(Object? json) {
    if (json is! Map) return null;
    final days = <int, List<OpenPeriod>>{};
    for (final (i, key) in keys.indexed) {
      final periods = json[key];
      if (periods is! List) continue;
      days[i + 1] = [
        for (final p in periods)
          if (p is List && p.length == 2)
            if ((OpenPeriod.parse(p[0] as String?), OpenPeriod.parse(p[1] as String?)) case (final int a, final int b)) OpenPeriod(a, b),
      ];
    }
    return days.isEmpty ? null : OpeningHours(days);
  }

  Map<String, dynamic> toJson() => {
        for (final e in days.entries)
          keys[e.key - 1]: [
            for (final p in e.value) [OpenPeriod.hhmm(p.open), OpenPeriod.hhmm(p.close)],
          ],
      };

  /// The periods on [weekday] (1 Monday to 7 Sunday): empty when closed,
  /// null when it hasn't said.
  List<OpenPeriod>? on(int weekday) => days[weekday];

  /// A day's hours in words: '6–10 am, 4–9 pm', 'Closed', or null.
  String? textOn(int weekday) {
    final periods = days[weekday];
    if (periods == null) return null;
    return periods.isEmpty ? 'Closed' : periods.map((p) => p.text).join(', ');
  }

  /// The week, days with the same hours together: Mon–Sat 6–10 am, 4–9 pm;
  /// Sun Closed.
  List<({String days, String hours})> summary() {
    final out = <({String days, String hours})>[];
    var start = 1;
    while (start <= 7) {
      final text = textOn(start);
      var end = start;
      while (end < 7 && textOn(end + 1) == text) {
        end++;
      }
      if (text != null) {
        final label = start == end ? names[start - 1] : '${names[start - 1]}–${names[end - 1]}';
        out.add((days: label, hours: text));
      }
      start = end + 1;
    }
    return out;
  }

  /// Open or closed at [bhutanNow] (Bhutan wall-clock time); null when it
  /// hasn't said for that day.
  OpenNow? at(DateTime bhutanNow) {
    final today = days[bhutanNow.weekday];
    if (today == null) return null;
    final minute = bhutanNow.hour * 60 + bhutanNow.minute;
    for (final p in today) {
      if (p.contains(minute)) return OpenNow(true, 'Open now · until ${OpenPeriod.label(p.close)}');
    }
    final later = today.where((p) => p.open > minute).firstOrNull;
    if (later != null) return OpenNow(false, 'Closed · opens ${OpenPeriod.label(later.open)}');
    return const OpenNow(false, 'Closed now');
  }
}
