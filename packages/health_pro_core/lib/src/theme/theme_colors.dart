import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_repository.dart';
import '../profiles/profile_repository.dart';
import 'brand.dart';

/// A colour they can give the app (Account -> Appearance -> App theme), as it
/// shows in each theme.
@immutable
class ThemeSwatch {
  /// Kept on the device: never rename one.
  final String id;
  final String name;

  /// On the light theme's white.
  final Color light;

  /// On the dark theme's navy: brighter, or softer.
  final Color dark;

  final Color? _text;
  final Color? _tint;
  final Color? _onTint;

  const ThemeSwatch(this.id, this.name,
      {required this.light, required this.dark, Color? text, Color? tint, Color? onTint})
      : _text = text,
        _tint = tint,
        _onTint = onTint;

  /// [light], deep enough to read as text on white (a focused field's label).
  Color get text => _text ?? light;

  /// A soft wash of [light] on white: a selected chip or segment.
  Color get tint => _tint ?? Color.lerp(Colors.white, light, 0.12)!;

  /// Text and icons on [tint].
  Color get onTint => _onTint ?? Color.lerp(text, Colors.black, 0.25)!;

  /// The dot in the picker, in the theme that shows.
  Color shown(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  @override
  bool operator ==(Object other) => other is ThemeSwatch && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The colours on offer. The first of each list is Health Pro's own.
abstract final class ThemePalette {
  /// The brand's orange: what's active, the main actions.
  static const orange = ThemeSwatch('orange', 'Orange',
      light: LightColors.orange,
      dark: BrandColors.orange,
      text: LightColors.orangeText,
      tint: Color(0xFFFFEDDF),
      onTint: Color(0xFF9A3A0B));

  /// The brand's navy: the light theme's buttons.
  static const navy = ThemeSwatch('navy', 'Navy',
      light: LightColors.navy, dark: Color(0xFF9CC2FF), tint: Color(0xFFE6ECF6), onTint: LightColors.navy);

  /// Bright enough to stand out on white and on navy.
  static const primaries = [
    orange,
    ThemeSwatch('blue', 'Blue', light: Color(0xFF2563EB), dark: Color(0xFF4F8DF7), text: Color(0xFF1D4ED8)),
    ThemeSwatch('green', 'Green', light: Color(0xFF16A34A), dark: Color(0xFF34C77B), text: Color(0xFF15803D)),
    ThemeSwatch('purple', 'Purple', light: Color(0xFF7C3AED), dark: Color(0xFFA47BF5), text: Color(0xFF6D28D9)),
    ThemeSwatch('teal', 'Teal', light: Color(0xFF0D9488), dark: Color(0xFF2DC2B0), text: Color(0xFF0F766E)),
    ThemeSwatch('red', 'Red', light: Color(0xFFDC2626), dark: Color(0xFFF05252), text: Color(0xFFB91C1C)),
    ThemeSwatch('pink', 'Pink', light: Color(0xFFDB2777), dark: Color(0xFFF0619E), text: Color(0xFFBE185D)),
    ThemeSwatch('cyan', 'Cyan', light: Color(0xFF0891B2), dark: Color(0xFF22B8D8), text: Color(0xFF0E7490)),
    ThemeSwatch('lime', 'Lime', light: Color(0xFF65A30D), dark: Color(0xFF9BCB3B), text: Color(0xFF4D7C0F)),
    ThemeSwatch('gold', 'Gold', light: Color(0xFFCA8A04), dark: Color(0xFFEAB308), text: Color(0xFFA16207)),
    ThemeSwatch('brown', 'Brown', light: Color(0xFF9A5B34), dark: Color(0xFFC08259), text: Color(0xFF7C4527)),
    ThemeSwatch('slate', 'Slate', light: Color(0xFF475569), dark: Color(0xFF94A3B8), text: Color(0xFF334155)),
  ];

  /// Deep in the light (white text on a button), soft on navy.
  static const accents = [
    navy,
    ThemeSwatch('indigo', 'Indigo', light: Color(0xFF3730A3), dark: Color(0xFFA5B4FC)),
    ThemeSwatch('forest', 'Forest', light: Color(0xFF14532D), dark: Color(0xFF8FD1A7)),
    ThemeSwatch('plum', 'Plum', light: Color(0xFF581C87), dark: Color(0xFFC9A7EB)),
    ThemeSwatch('wine', 'Wine', light: Color(0xFF881337), dark: Color(0xFFF2A7BD)),
    ThemeSwatch('pine', 'Pine', light: Color(0xFF134E4A), dark: Color(0xFF8ED5CB)),
    ThemeSwatch('ocean', 'Ocean', light: Color(0xFF0C4A6E), dark: Color(0xFF8DCBEA)),
    ThemeSwatch('olive', 'Olive', light: Color(0xFF3F4A15), dark: Color(0xFFC3CE8E)),
    ThemeSwatch('bronze', 'Bronze', light: Color(0xFF7C3A10), dark: Color(0xFFE8BC8C)),
    ThemeSwatch('cocoa', 'Cocoa', light: Color(0xFF45291D), dark: Color(0xFFCCAA92)),
    ThemeSwatch('charcoal', 'Charcoal', light: Color(0xFF1F2937), dark: Color(0xFFBAC3CF)),
  ];

  static ThemeSwatch _find(List<ThemeSwatch> swatches, String? id) =>
      swatches.firstWhere((s) => s.id == id, orElse: () => swatches.first);
}

/// The app's two colours. Health Pro's orange and navy until they pick others.
@immutable
class ThemeColors {
  /// What's active, the main action, focus, switches; the dark theme's
  /// buttons.
  final ThemeSwatch primary;

  /// The light theme's buttons; selected chips and segments in the dark.
  final ThemeSwatch accent;

  const ThemeColors({this.primary = ThemePalette.orange, this.accent = ThemePalette.navy});

  /// From what was kept on the device; an id no longer offered is the default.
  factory ThemeColors.fromIds({String? primary, String? accent}) => ThemeColors(
      primary: ThemePalette._find(ThemePalette.primaries, primary),
      accent: ThemePalette._find(ThemePalette.accents, accent));

  static const standard = ThemeColors();

  bool get isStandard => this == standard;

  @override
  bool operator ==(Object other) => other is ThemeColors && other.primary == primary && other.accent == accent;

  @override
  int get hashCode => Object.hash(primary, accent);

  @override
  String toString() => 'ThemeColors(${primary.id}, ${accent.id})';
}

/// The signed-in person's own colours (Account -> Appearance), kept on their
/// account so every device they sign in on shows them. Signed out (the
/// welcome and sign-in pages), Health Pro's orange and navy for everyone.
final themeColorsProvider = NotifierProvider<ThemeColorsController, ThemeColors>(ThemeColorsController.new);

class ThemeColorsController extends Notifier<ThemeColors> {
  static String _key(String part, String user) => 'theme_$part.$user';

  /// [user]'s colours as this device last knew them; Health Pro's own for
  /// nobody. Read before the first frame (main.dart), so they open in them
  /// while their account is asked.
  static Future<ThemeColors> saved(String? user) async {
    if (user == null) return ThemeColors.standard;
    try {
      final prefs = await SharedPreferences.getInstance();
      return ThemeColors.fromIds(primary: prefs.getString(_key('primary', user)), accent: prefs.getString(_key('accent', user)));
    } catch (_) {
      return ThemeColors.standard;
    }
  }

  static Future<void> _keepOnDevice(String user, ThemeColors colors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key('primary', user), colors.primary.id);
      await prefs.setString(_key('accent', user), colors.accent.id);
    } catch (_) {
      // Not kept on this device; their account still has them.
    }
  }

  /// [initial] is [user]'s, read before the first frame.
  ThemeColorsController([ThemeColors initial = ThemeColors.standard, String? user]) {
    if (user != null) _known[user] = initial;
  }

  /// Each account's colours, as last read or picked here.
  final _known = <String, ThemeColors>{};
  String? _user;

  /// Counts their picks, so an answer asked for before one can't undo it.
  int _picks = 0;

  /// Picks reach the account one after another, so the last one stays.
  Future<void> _saving = Future.value();

  @override
  ThemeColors build() {
    final user = _user = ref.watch(currentUserIdProvider);
    if (user == null) return ThemeColors.standard;
    var live = true;
    ref.onDispose(() => live = false);
    final picks = _picks;
    bool current() => live && picks == _picks;
    var answered = false;
    // What this device last knew for them, until their account answers.
    if (!_known.containsKey(user)) {
      saved(user).then((colors) {
        if (answered || !current()) return;
        state = _known[user] = colors;
      });
    }
    _fromAccount(user).then((colors) {
      if (colors == null || !current()) return;
      answered = true;
      if (colors != state) state = colors;
      _known[user] = colors;
      _keepOnDevice(user, colors);
    });
    return _known[user] ?? ThemeColors.standard;
  }

  /// Null when it can't be asked (offline, or the account has no profile):
  /// the device's stay.
  Future<ThemeColors?> _fromAccount(String user) async {
    try {
      final ids = await ref.read(profileRepositoryProvider).theme(user);
      return ids == null ? null : ThemeColors.fromIds(primary: ids.primary, accent: ids.accent);
    } catch (_) {
      return null;
    }
  }

  Future<void> setPrimary(ThemeSwatch swatch) => _set(ThemeColors(primary: swatch, accent: state.accent));

  Future<void> setAccent(ThemeSwatch swatch) => _set(ThemeColors(primary: state.primary, accent: swatch));

  /// Back to Health Pro's orange and navy.
  Future<void> reset() => _set(ThemeColors.standard);

  Future<void> _set(ThemeColors colors) async {
    final user = _user;
    // Signed out, the app wears Health Pro's own.
    if (user == null) return;
    _picks++;
    state = _known[user] = colors;
    await _keepOnDevice(user, colors);
    Future<void> save() async {
      try {
        // Health Pro's own is kept as none, so it follows if the defaults change.
        await ref.read(profileRepositoryProvider).setTheme(user,
            primary: colors.primary == ThemePalette.orange ? null : colors.primary.id,
            accent: colors.accent == ThemePalette.navy ? null : colors.accent.id);
      } catch (_) {
        // Offline: this device keeps them; the account has the last pick that reached it.
      }
    }

    await (_saving = _saving.then((_) => save()));
  }
}
