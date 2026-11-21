import 'package:flutter/material.dart';

/// Someone in a list (users, staff, trainers, members): the profile photo
/// they uploaded, in a circle, or their initials on a tint of [color] while
/// there's none. The initials also show while the photo loads and when it
/// won't.
class PersonAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double radius;

  /// The initials' colour (the theme's primary when null).
  final Color? color;

  const PersonAvatar({super.key, required this.name, this.photoUrl, this.radius = 20, this.color});

  /// 'Pema K Dorji' -> 'PD'; one word -> its first letter; nothing -> '?'.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    return (parts.length > 1 ? first + parts.last.characters.first : first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    final size = radius * 2;
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(initialsOf(name), style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: radius * 0.8)),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return initials;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          semanticLabel: name,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          frameBuilder: (context, child, frame, sync) => frame == null && !sync ? initials : child,
          errorBuilder: (_, __, ___) => initials,
        ),
      ),
    );
  }
}
