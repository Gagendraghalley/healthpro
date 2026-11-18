import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';
import '../legal/legal_pages.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';
import '../theme/theme_picker.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/dashboard_kit.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/motion.dart';
import 'profile.dart';
import 'profile_repository.dart';

/// The signed-in user's page: who they are (a cover in their theme's colours,
/// their initials, member code and details), how the app looks, signing out
/// and deleting the account.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  /// From this width the details and the preferences sit side by side.
  static const _besideFrom = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    const gap = SizedBox(height: 20);
    return AppPage(
      title: 'Account',
      body: AsyncValueView<Profile?>(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (p) => ListView(
          padding: pagePadding(context),
          children: [
            const FadeSlideIn(
              child: _Heading(title: 'Account settings', note: 'Your profile, how Health Pro looks, and signing in.'),
            ),
            if (p != null) ...[
              FadeSlideIn(delay: const Duration(milliseconds: 60), child: _ProfileHero(profile: p)),
              gap,
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                const preferences = FadeSlideIn(delay: Duration(milliseconds: 180), child: _PreferencesCard());
                if (p == null) return preferences;
                final details = FadeSlideIn(delay: const Duration(milliseconds: 120), child: _DetailsCard(profile: p));
                if (constraints.maxWidth < _besideFrom) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, gap, preferences]);
                }
                // Side by side, the two cards come out the same height.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [Expanded(child: details), const SizedBox(width: 20), const Expanded(child: preferences)],
                  ),
                );
              },
            ),
            gap,
            FadeSlideIn(
              delay: const Duration(milliseconds: 240),
              child: _AccountCard(onSignOut: () => _signOut(context, ref), onDelete: () => _deleteAccount(context, ref)),
            ),
            const SizedBox(height: 12),
            const LegalLinks(),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go(CoreRoutes.welcome);
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: 'Delete your account?',
      message: 'Your profile, memberships and check-ins are deleted for good. '
          "Payments stay in the venues' records, without your name. This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final done = await runAction(context, () => ref.read(authRepositoryProvider).deleteAccount());
    if (done && context.mounted) context.go(CoreRoutes.welcome);
  }
}

/// A page's title and what's on it, as on My dashboard.
class _Heading extends StatelessWidget {
  final String title;
  final String note;

  const _Heading({required this.title, required this.note});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink.heading, height: 1.2)),
          const SizedBox(height: 4),
          Text(note, style: TextStyle(color: context.brand.muted, fontSize: 14.5)),
        ],
      ),
    );
  }
}

/// The big cards' look: the card colour, a hairline, the theme's shadow.
BoxDecoration _cardDecoration(BuildContext context) {
  final ink = ConsoleInk.of(context);
  return BoxDecoration(
    color: ink.card,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: context.brand.glassBorder),
    boxShadow: ink.shadow,
  );
}

/// Who they are, across the top: a band in their theme's colours, their
/// initials over its edge, their name and email, member code and status, and
/// the way to edit them.
class _ProfileHero extends StatelessWidget {
  final Profile profile;

  const _ProfileHero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final cover = wide ? 112.0 : 92.0;
        final avatar = wide ? 96.0 : 80.0;
        final side = wide ? 28.0 : 20.0;
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profile.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: wide ? 24 : 21, fontWeight: FontWeight.w800, color: ink.heading, height: 1.2, letterSpacing: -0.2),
            ),
            if (profile.email != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.mail_outline_rounded, size: 16, color: brand.muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(profile.email!,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 14.5)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (profile.memberCode.isNotEmpty) _MemberCode(code: profile.memberCode),
                if (profile.isAdmin) StatusChip(label: 'Super admin', color: brand.accent, icon: Icons.shield_outlined),
                if (profile.isActive)
                  StatusChip(label: 'Active', color: brand.success, icon: Icons.verified_rounded)
                else
                  StatusChip(label: 'Turned off', color: brand.warning, icon: Icons.pause_circle_outline_rounded),
              ],
            ),
          ],
        );
        final edit = FilledButton.icon(
          onPressed: () => context.push(CoreRoutes.editProfile),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit profile'),
        );
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: _cardDecoration(context),
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, right: 0, height: cover, child: const _Cover()),
              Padding(
                padding: wide
                    ? EdgeInsets.fromLTRB(side + avatar + 20, cover + 18, side, 26)
                    : EdgeInsets.fromLTRB(side, cover + avatar / 2 + 14, side, 20),
                child: wide
                    ? Row(children: [Expanded(child: identity), const SizedBox(width: 16), edit])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [identity, const SizedBox(height: 18), edit],
                      ),
              ),
              Positioned(
                  left: side,
                  top: cover - avatar / 2,
                  child: _Avatar(name: profile.displayName, size: avatar, photo: _networkPhoto(profile.avatarUrl))),
            ],
          ),
        );
      },
    );
  }
}

/// The colour they lead with, light or dark: what the cover and the avatar
/// start from.
Color _leadColour(BuildContext context) => context.brand.pick(context.colors.primary, context.colors.secondary);

/// The band across the top of the profile: the theme's two colours, a soft
/// sheen and a few faint rings.
class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) {
    final from = _leadColour(context);
    final to = context.brand.accent;
    Widget ring(double size, double alpha) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: alpha * 0.35),
            border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 1.2),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [from, Color.lerp(from, to, 0.55)!, to]),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Positioned(right: -50, top: -80, child: ring(220, 0.18)),
          Positioned(right: 130, bottom: -70, child: ring(130, 0.12)),
        ],
      ),
    );
  }
}

/// Their photo, or their initials, in a circle, raised over the cover:
/// ringed in the card's colour with a shadow so it stands off it. The
/// initials show while the photo loads, and when it won't.
class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final ImageProvider? photo;

  const _Avatar({required this.name, required this.size, this.photo});

  @override
  Widget build(BuildContext context) {
    final from = _leadColour(context);
    // White on a deep colour; dark ink on a pale one (cocoa in the dark is beige).
    final letters = ThemeData.estimateBrightnessForColor(from) == Brightness.dark ? Colors.white : LightColors.ink;
    final initials = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(from, Colors.white, 0.12)!, Color.lerp(from, Colors.black, 0.18)!],
        ),
      ),
      child: Center(
        child: Text(
          _initials(name),
          style: TextStyle(color: letters, fontSize: size * 0.32, fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ConsoleInk.of(context).card,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: photo == null
          ? initials
          : ClipOval(
              child: Image(
                image: photo!,
                fit: BoxFit.cover,
                semanticLabel: name,
                frameBuilder: (context, child, frame, sync) => frame == null && !sync ? initials : child,
                errorBuilder: (_, __, ___) => initials,
              ),
            ),
    );
  }
}

/// The saved photo at [url], if there is one.
ImageProvider? _networkPhoto(String? url) => url == null || url.isEmpty ? null : NetworkImage(url);

/// 'Pema Dorji' -> 'PD'; one word or an email -> its first letter.
String _initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  if (words.length == 1 || name.contains('@')) return first.toUpperCase();
  return (first + words.last.characters.first).toUpperCase();
}

/// Their member code, which gym staff can type at check-in; a tap copies it.
class _MemberCode extends StatelessWidget {
  final String code;

  const _MemberCode({required this.code});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final muted = context.brand.muted;
    return Tooltip(
      message: 'Copy member code',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) showFeedback(context, 'Member code copied');
          },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
            decoration: BoxDecoration(
              color: ink.tint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.brand.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_2_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Text('Member code', style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text(code,
                    style: TextStyle(color: ink.heading, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(width: 8),
                Icon(Icons.copy_rounded, size: 14, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What Health Pro knows them by, with the way to change it.
class _DetailsCard extends StatelessWidget {
  final Profile profile;

  const _DetailsCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (Icons.badge_outlined, 'Full name', profile.fullName),
      (Icons.mail_outline_rounded, 'Email', profile.email),
      (Icons.phone_outlined, 'Phone', profile.phone),
      (Icons.place_outlined, 'Dzongkhag', profile.dzongkhag),
    ];
    return ConsoleCard(
      icon: Icons.person_outline_rounded,
      title: 'Personal details',
      trailing: ConsoleLink(label: 'Edit', onPressed: () => context.push(CoreRoutes.editProfile)),
      child: Column(
        children: [
          for (final (i, (icon, label, value)) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: context.brand.glassBorder),
            _Detail(icon: icon, label: label, value: value),
          ],
        ],
      ),
    );
  }
}

/// A detail: what it is, small, over its value ('Not added' in grey without
/// one).
class _Detail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _Detail({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final muted = context.brand.muted;
    final has = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: ink.tint, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  has ? value!.trim() : 'Not added',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: has ? ink.heading : muted,
                    fontSize: 15,
                    fontWeight: has ? FontWeight.w700 : FontWeight.w500,
                    fontStyle: has ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Light or dark (each a small picture of the app), their colours, and
/// keeping things still.
class _PreferencesCard extends ConsumerWidget {
  const _PreferencesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Light or dark; before they've chosen, what the phone shows.
    final mode = switch (ref.watch(themeModeProvider)) {
      ThemeMode.system => Theme.of(context).brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      final chosen => chosen,
    };
    final brand = context.brand;
    void pick(ThemeMode m) => ref.read(themeModeProvider.notifier).set(m);
    final still = ref.watch(reduceMotionProvider);
    void keepStill(bool v) => ref.read(reduceMotionProvider.notifier).set(v);
    return ConsoleCard(
      icon: Icons.tune_rounded,
      title: 'Preferences',
      // Transparent, so the rows' ink shows on the card.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('APPEARANCE',
                style: TextStyle(color: brand.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, option) in const [ThemeMode.light, ThemeMode.dark].indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _ModeOption(mode: option, selected: mode == option, onTap: () => pick(option))),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const ThemeColorsTile(),
            Divider(height: 9, color: brand.glassBorder),
            // Off until they turn it on, whatever the device's own setting.
            MergeSemantics(
              child: SettingRow(
                icon: Icons.motion_photos_paused_outlined,
                title: 'Reduce motion',
                subtitle: 'Keep pages and numbers still: no entrances, count-ups or floating cards',
                trailing: Switch(value: still, onChanged: keepStill),
                onTap: () => keepStill(!still),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Light or dark as a card to pick: a small picture of the app in it, its
/// name, and a tick on the one in use.
class _ModeOption extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({required this.mode, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final ink = ConsoleInk.of(context);
    final dark = mode == ThemeMode.dark;
    final label = dark ? 'Dark' : 'Light';
    final duration = Motion.of(context, Motion.dropdown);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.ease,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? brand.accent.withValues(alpha: 0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? brand.accent : brand.glassBorder, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MiniApp(dark: dark),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        size: 17, color: selected ? brand.accent : brand.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(label, style: TextStyle(color: ink.heading, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(selected),
                        size: 20,
                        color: selected ? brand.accent : brand.fieldBorder,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small picture of the app, light or dark whichever is showing: a side
/// menu, a bar and two cards, with a touch of their colour.
class _MiniApp extends StatelessWidget {
  final bool dark;

  const _MiniApp({required this.dark});

  @override
  Widget build(BuildContext context) {
    final accent = context.brand.accent;
    final page = dark ? BrandColors.night : LightColors.background;
    final panel = dark ? BrandColors.slateNavy : LightColors.card;
    final line = dark ? Colors.white.withValues(alpha: 0.12) : LightColors.border;
    Widget bar(Color color, {double? width, double height = 4}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        );
    BoxDecoration box(double radius) =>
        BoxDecoration(color: panel, borderRadius: BorderRadius.circular(radius), border: Border.all(color: line));
    return Container(
      height: 78,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(color: page, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 24,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            decoration: box(5),
            child: Column(children: [bar(accent), const SizedBox(height: 5), bar(line), const SizedBox(height: 5), bar(line)]),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 11, decoration: box(4)),
                const SizedBox(height: 5),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, mark) in [accent, line].indexed) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: box(5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [bar(mark, width: 14), const SizedBox(height: 4), bar(line, width: double.infinity)],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Signing out, and deleting the account for good: side by side on a wide
/// screen, one over the other on a narrow one.
class _AccountCard extends StatelessWidget {
  final VoidCallback onSignOut;
  final VoidCallback onDelete;

  const _AccountCard({required this.onSignOut, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ConsoleCard(
      icon: Icons.manage_accounts_outlined,
      title: 'Account',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The button at the end of the row, or under it on a phone.
          Widget action(
              {required IconData icon, required String title, required String subtitle, required Widget button, Color? color}) {
            if (constraints.maxWidth >= 480) {
              return SettingRow(icon: icon, color: color, title: title, subtitle: subtitle, trailing: button);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingRow(icon: icon, color: color, title: title, subtitle: subtitle),
                Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 0), child: button),
              ],
            );
          }

          final signOut = action(
            icon: Icons.logout_rounded,
            title: 'Sign out',
            subtitle: 'You can sign back in any time with your email.',
            button: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sign out'),
            ),
          );
          final delete = action(
            icon: Icons.delete_outline_rounded,
            color: brand.danger,
            title: 'Delete account',
            subtitle: "Your profile, memberships and check-ins are deleted for good. This can't be undone.",
            button: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: brand.danger,
                side: BorderSide(color: brand.danger.withValues(alpha: 0.45)),
              ),
              onPressed: onDelete,
              child: const Text('Delete account'),
            ),
          );
          // Side by side only where each half still has room for its words.
          if (constraints.maxWidth < 1100) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [signOut, Divider(height: 24, color: brand.glassBorder), delete],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: signOut),
                VerticalDivider(width: 48, color: brand.glassBorder),
                Expanded(child: delete),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Their own profile, across the whole page: a cover with their photo (which
/// they add, change or take off here), then their personal details and the
/// email they sign in with, each beside what it's for on a wide window.
/// Cancel and Save stay at the foot of the page; a new photo is only uploaded
/// when they save.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _dzongkhag;
  bool _loaded = false;
  bool _busy = false;

  /// A photo they picked, uploaded when they save.
  ({Uint8List bytes, String contentType})? _newPhoto;

  /// They took their saved photo off; it goes when they save.
  bool _photoRemoved = false;

  /// The profile-photos bucket takes up to this.
  static const _maxPhotoBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _fill(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.fullName;
    _phone.text = p.phone ?? '';
    _dzongkhag = p.dzongkhag;
  }

  /// The photo as it will be once they save: the one just picked, the saved
  /// one, or none.
  ImageProvider? _shownPhoto(Profile p) {
    final picked = _newPhoto;
    if (picked != null) return MemoryImage(picked.bytes);
    return _photoRemoved ? null : _networkPhoto(p.avatarUrl);
  }

  bool _changed(Profile p) =>
      _name.text.trim() != p.fullName.trim() ||
      _phone.text.trim() != (p.phone ?? '') ||
      _dzongkhag != p.dzongkhag ||
      _newPhoto != null ||
      (_photoRemoved && p.avatarUrl != null);

  Future<void> _pickPhoto({bool camera = false}) async {
    ({Uint8List bytes, String contentType})? picked;
    await runAction(context, () async => picked = await pickPhoto(context, camera: camera, imageQuality: 85));
    final photo = picked;
    if (photo == null || !mounted) return;
    if (photo.bytes.length > _maxPhotoBytes) {
      showFeedback(context, 'That photo is too big. Choose one of up to 5 MB.', problem: true);
      return;
    }
    setState(() {
      _newPhoto = photo;
      _photoRemoved = false;
    });
  }

  void _removePhoto() => setState(() {
        _newPhoto = null;
        _photoRemoved = true;
      });

  Future<void> _save(Profile p) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final repo = ref.read(profileRepositoryProvider);
    final phone = _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text);
    final picked = _newPhoto;
    final ok = await runAction(
      context,
      () async {
        var photo = _photoRemoved ? null : p.avatarUrl;
        if (picked != null) photo = await repo.uploadPhoto(p.id, picked);
        await repo.update(p.id, fullName: _name.text, phone: phone, dzongkhag: _dzongkhag, avatarUrl: photo);
        final old = p.avatarUrl;
        if (old != null && old != photo) await repo.removePhoto(p.id, old);
      },
      success: 'Profile saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(myProfileProvider);
      _leave();
    }
  }

  /// Back where they came from; to Account when they opened this page
  /// straight (from My dashboard, or a link).
  void _leave() => context.canPop() ? context.pop() : context.go(CoreRoutes.account);

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    final me = profile.valueOrNull;
    if (me != null) _fill(me);
    return AppPage(
      title: 'Edit profile',
      bottomBar: me == null ? null : _actionBar(me),
      body: AsyncValueView<Profile?>(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          return Form(
            key: _form,
            child: ListView(
              padding: pagePadding(context),
              children: [
                const FadeSlideIn(
                  child: _Heading(title: 'Edit profile', note: 'Your photo, name, phone number and dzongkhag.'),
                ),
                FadeSlideIn(delay: const Duration(milliseconds: 60), child: _photoCard(p)),
                const SizedBox(height: 20),
                FadeSlideIn(delay: const Duration(milliseconds: 120), child: _detailsCard(p)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The cover in their theme's colours, their photo over its edge (tap it,
  /// or its camera badge, for a new one), who they are, and the photo's
  /// buttons.
  Widget _photoCard(Profile p) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    final photo = _shownPhoto(p);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final cover = wide ? 136.0 : 100.0;
        final avatar = wide ? 132.0 : 104.0;
        final side = wide ? 32.0 : 20.0;
        final who = ListenableBuilder(
          listenable: _name,
          builder: (context, _) {
            final shown = _name.text.trim().isEmpty ? p.displayName : _name.text.trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shown,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ink.heading,
                        fontSize: wide ? 24 : 21,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.2)),
                if (p.email != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.mail_outline_rounded, size: 16, color: brand.muted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(p.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: brand.muted, fontSize: 14.5)),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
        final buttons = Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickPhoto,
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(photo == null ? 'Upload photo' : 'Change photo'),
            ),
            if (!kIsWeb)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickPhoto(camera: true),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take photo'),
              ),
            if (photo != null)
              TextButton.icon(
                onPressed: _busy ? null : _removePhoto,
                style: TextButton.styleFrom(foregroundColor: brand.danger),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove'),
              ),
          ],
        );
        final hint = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 15, color: brand.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _newPhoto != null
                    ? 'New photo picked. It\'s saved when you save your changes.'
                    : 'JPG, PNG or WebP, up to 5 MB. A clear photo of your face works best.',
                style: TextStyle(color: brand.muted, fontSize: 13, height: 1.35),
              ),
            ),
          ],
        );
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: _cardDecoration(context),
          child: Stack(
            children: [
              Positioned(left: 0, top: 0, right: 0, height: cover, child: const _Cover()),
              Padding(
                padding: wide
                    ? EdgeInsets.fromLTRB(side + avatar + 24, cover + 20, side, 26)
                    : EdgeInsets.fromLTRB(side, cover + avatar / 2 + 14, side, 22),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [who, const SizedBox(height: 14), hint])),
                          const SizedBox(width: 24),
                          Flexible(child: Align(alignment: Alignment.topRight, child: buttons)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [who, const SizedBox(height: 18), buttons, const SizedBox(height: 14), hint],
                      ),
              ),
              Positioned(
                left: side,
                top: cover - avatar / 2,
                child: _PhotoPicker(
                  name: _name,
                  fallbackName: p.displayName,
                  size: avatar,
                  photo: photo,
                  onPick: _busy ? null : _pickPhoto,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Their details, then the email they sign in with, each a section with
  /// what it's for.
  Widget _detailsCard(Profile p) {
    final line = Divider(height: 1, color: context.brand.glassBorder);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormSection(
            icon: Icons.person_outline_rounded,
            title: 'Personal details',
            note: 'Your name, phone number and dzongkhag.',
            child: _fields(),
          ),
          line,
          _FormSection(
            icon: Icons.lock_outline_rounded,
            title: 'Sign-in',
            note: 'You sign in with this email.',
            child: TextFormField(
              initialValue: p.email ?? '',
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Name and phone side by side where there's room, the dzongkhag under them.
  Widget _fields() {
    final name = TextFormField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.badge_outlined)),
      validator: (v) => Validators.required(v, 'Your name'),
    );
    final phone = TextFormField(
      controller: _phone,
      keyboardType: TextInputType.phone,
      decoration:
          const InputDecoration(labelText: 'Phone number', hintText: 'e.g. 17123456', prefixIcon: Icon(Icons.phone_outlined)),
      validator: Validators.phone,
    );
    final dzongkhag = DzongkhagField(
      value: _dzongkhag,
      required: false,
      icon: Icons.place_outlined,
      onChanged: (v) => setState(() => _dzongkhag = v),
    );
    const gap = SizedBox(height: 16, width: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 520
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [name, gap, phone])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: name), gap, Expanded(child: phone)],
                ),
        ),
        gap,
        dzongkhag,
      ],
    );
  }

  /// At the foot of the page: whether anything changed, Cancel and Save.
  Widget _actionBar(Profile p) {
    return ListenableBuilder(
      listenable: Listenable.merge([_name, _phone]),
      builder: (context, _) {
        final brand = context.brand;
        final changed = _changed(p);
        final cancel = OutlinedButton(onPressed: _busy ? null : _leave, child: const Text('Cancel'));
        final save = FilledButton.icon(
          onPressed: _busy ? null : () => _save(p),
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Save changes'),
        );
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: pageGutter(context), vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Row(children: [Expanded(child: cancel), const SizedBox(width: 12), Expanded(flex: 2, child: save)]);
              }
              return Row(
                children: [
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: changed ? 1 : 0,
                      duration: reduceMotion(context) ? Duration.zero : Motion.hover,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: brand.warning, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('You have unsaved changes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: brand.muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  cancel,
                  const SizedBox(width: 12),
                  save,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Their photo (or initials, following the name being typed) over the
/// cover, with a camera badge; tapping either picks a new photo.
class _PhotoPicker extends StatelessWidget {
  final TextEditingController name;
  final String fallbackName;
  final double size;
  final ImageProvider? photo;
  final VoidCallback? onPick;

  const _PhotoPicker({required this.name, required this.fallbackName, required this.size, this.photo, this.onPick});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final badge = size * 0.3;
    return Semantics(
      button: true,
      label: photo == null ? 'Upload a profile photo' : 'Change your profile photo',
      onTap: onPick,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ListenableBuilder(
            listenable: name,
            builder: (context, _) => _Avatar(
              name: name.text.trim().isEmpty ? fallbackName : name.text.trim(),
              size: size,
              photo: photo,
            ),
          ),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onPick, excludeFromSemantics: true),
            ),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Tooltip(
              message: photo == null ? 'Upload photo' : 'Change photo',
              child: Material(
                color: brand.highlight,
                shape: CircleBorder(side: BorderSide(color: ConsoleInk.of(context).card, width: 3)),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPick,
                  excludeFromSemantics: true,
                  child: SizedBox.square(
                    dimension: badge,
                    child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: badge * 0.48),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A part of the form: its icon, title and what it's for at the left on a
/// wide window (above it on a narrow one), its fields beside them.
class _FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final Widget child;

  const _FormSection({required this.icon, required this.title, required this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final label = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: brand.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 19, color: brand.accentText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: ink.heading, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(note, style: TextStyle(color: brand.muted, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
        );
        return Padding(
          padding: EdgeInsets.all(wide ? 30 : 20),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 300, child: label),
                    const SizedBox(width: 48),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: child),
                      ),
                    ),
                  ],
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, const SizedBox(height: 20), child]),
        );
      },
    );
  }
}
