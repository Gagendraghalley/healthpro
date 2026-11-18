import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../auth/auth_repository.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../venues/venue.dart';
import '../venues/venue_repository.dart';

// The account menu (their account, sign out): at the top right of every
// signed-in page, and under the side menu. Light or dark is the bar's own
// switch (ThemeModeButton).

/// The account menu's choices.
List<PopupMenuEntry<String>> accountMenuEntries() => const [
      PopupMenuItem(
        value: 'account',
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: _MenuRow(icon: Icons.person_outline_rounded, title: 'Account', subtitle: 'Profile, appearance and privacy'),
      ),
      PopupMenuDivider(height: 9),
      PopupMenuItem(
        value: 'out',
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: _MenuRow(icon: Icons.logout_rounded, title: 'Sign out', danger: true),
      ),
    ];

/// One choice in the account menu: its icon on a soft tile, a title and a
/// quiet line under it. Sign out ([danger]) in red, without the arrow.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;

  const _MenuRow({required this.icon, required this.title, this.subtitle, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tint = danger ? brand.danger : brand.accent;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: danger ? brand.danger : brand.accentText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: danger ? brand.danger : context.colors.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(subtitle!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 12)),
                ),
            ],
          ),
        ),
        if (!danger) Icon(Icons.chevron_right_rounded, size: 18, color: brand.muted),
      ],
    );
  }
}

/// What the account menu says they are: super admin, Health Pro team, their
/// role at each venue they run ('Owner · Iron Gym'), or 'Member' when none.
@visibleForTesting
List<String> accountRoleLabels(PlatformAccess access, List<MyVenue> venues) {
  final roles = [
    if (access.isSuperAdmin) 'Super admin' else if (access.isTeam) 'Health Pro team',
    for (final v in venues) '${v.roleName} · ${v.venue.name}',
  ];
  return roles.isEmpty ? const ['Member'] : roles;
}

/// The top of the account menu: who is signed in, larger, with a badge for
/// each role they have (the first three, then how many more).
class _AccountHeader extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final List<String> roles;

  const _AccountHeader({required this.name, required this.photoUrl, required this.roles});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          AccountAvatar(name: name, photoUrl: photoUrl, radius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? 'You' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w700, fontSize: 15)),
                if (roles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final role in roles.take(3)) _RoleBadge(role),
                        if (roles.length > 3) _RoleBadge('+${roles.length - 3} more'),
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

/// One role in the account menu's header, as a soft pill.
class _RoleBadge extends StatelessWidget {
  final String label;

  const _RoleBadge(this.label);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: brand.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: brand.accentText, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.2)),
    );
  }
}

/// Does what [value], one of [accountMenuEntries], says.
Future<void> chooseFromAccountMenu(BuildContext context, WidgetRef ref, String value) async {
  switch (value) {
    case 'account':
      context.go(CoreRoutes.account);
    case 'out':
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go(CoreRoutes.welcome);
  }
}

/// Their profile photo in a circle; their initial in an orange one when they
/// have no photo, while it loads, or when it won't.
class AccountAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double radius;

  const AccountAvatar({super.key, required this.name, this.photoUrl, this.radius = 17});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final letter = CircleAvatar(
      radius: radius,
      backgroundColor: context.brand.highlight,
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85)),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return letter;
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          semanticLabel: name,
          cacheWidth: (radius * 2 * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (context, child, frame, sync) => frame == null && !sync ? letter : child,
          errorBuilder: (_, __, ___) => letter,
        ),
      ),
    );
  }
}

/// Top right of a signed-in page: their photo (or initial), opening the account menu
/// under who is signed in.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final name = (profile?.fullName ?? '').trim();
    final access = ref.watch(myAccessProvider).valueOrNull;
    final venues = ref.watch(myVenuesProvider).valueOrNull;
    // Nothing until both have loaded, so a gym owner never flashes as 'Member'.
    final roles = access == null || venues == null ? const <String>[] : accountRoleLabels(access, venues);
    return PopupMenuButton<String>(
      tooltip: 'Account and settings',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      menuPadding: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints.tightFor(width: 280),
      clipBehavior: Clip.antiAlias,
      onSelected: (value) => chooseFromAccountMenu(context, ref, value),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 0,
          padding: EdgeInsets.zero,
          child: _AccountHeader(name: name, photoUrl: profile?.avatarUrl, roles: roles),
        ),
        const PopupMenuDivider(height: 9),
        ...accountMenuEntries(),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        // A thin orange ring around it in the light theme.
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: context.brand.pick(context.brand.accent.withValues(alpha: 0.35), Colors.transparent), width: 1.5),
          ),
          child: AccountAvatar(name: name, photoUrl: profile?.avatarUrl, radius: 15),
        ),
      ),
    );
  }
}
