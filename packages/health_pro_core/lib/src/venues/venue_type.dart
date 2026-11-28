import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'venue_repository.dart';

/// A kind of service on Health Pro (venue_types): Gym, Swimming Pool,
/// Cycling, Wellness Centre... The Health Pro team keeps the list in Admin ->
/// Service types; each is run by a module ([moduleKey]), which gives
/// its organisations their pages (a pool's packages, members and check-in
/// are the gym module's).
class VenueType {
  final String key;
  final String moduleKey;
  final String name;
  final String? description;

  /// One of [VenueTypeIcons.all]'s keys.
  final String icon;

  /// What organisations of this type often have: ticks on their form.
  final List<String> facilities;
  final int sortOrder;

  /// Off: no new organisations of this type; those registered keep it.
  final bool isActive;

  /// Its card on Services: one of [VenueTypeColors.all]'s keys (null for
  /// the brand's), a cover photo's address, and whether it shows (Coming
  /// soon) before any organisation of the type is verified.
  final String? color;
  final String? photo;
  final bool showWhenEmpty;

  const VenueType({
    required this.key,
    required this.moduleKey,
    required this.name,
    this.description,
    this.icon = VenueTypeIcons.fallback,
    this.facilities = const [],
    this.sortOrder = 100,
    this.isActive = true,
    this.color,
    this.photo,
    this.showWhenEmpty = true,
  });

  IconData get iconData => VenueTypeIcons.of(icon);

  /// Its colour, or [fallback] without one.
  Color colorOr(Color fallback) => VenueTypeColors.of(color) ?? fallback;

  factory VenueType.fromJson(Map<String, dynamic> json) => VenueType(
        key: json['key'] as String,
        moduleKey: json['module_key'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String? ?? VenueTypeIcons.fallback,
        facilities: (json['facilities'] as List?)?.cast<String>() ?? const [],
        sortOrder: json['sort_order'] as int? ?? 100,
        isActive: json['is_active'] as bool? ?? true,
        color: json['color'] as String?,
        photo: json['photo'] as String?,
        showWhenEmpty: json['show_when_empty'] as bool? ?? true,
      );
}

/// What the type form sends (save_venue_type).
class VenueTypeDraft {
  final String name;
  final String description;
  final String icon;
  final List<String> facilities;
  final int sortOrder;
  final bool active;
  final String? color;
  final String? photo;
  final bool showWhenEmpty;

  const VenueTypeDraft({
    required this.name,
    this.description = '',
    this.icon = VenueTypeIcons.fallback,
    this.facilities = const [],
    this.sortOrder = 100,
    this.active = true,
    this.color,
    this.photo,
    this.showWhenEmpty = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'description': description.trim(),
        'icon': icon,
        'facilities': [for (final f in facilities) if (f.trim().isNotEmpty) f.trim()],
        'sort_order': sortOrder,
        'active': active,
        'color': color,
        'photo': photo,
        'show_when_empty': showWhenEmpty,
      };
}

/// The colours a service type's card can have, by the key venue_types.color
/// keeps: strong enough for its icon on white and on the dark theme's cards.
abstract final class VenueTypeColors {
  static const all = <String, (Color, String)>{
    'orange': (Color(0xFFF97316), 'Orange'),
    'blue': (Color(0xFF1F6FD6), 'Blue'),
    'green': (Color(0xFF1B8A4B), 'Green'),
    'teal': (Color(0xFF0E9384), 'Teal'),
    'violet': (Color(0xFF7C5CDB), 'Violet'),
    'amber': (Color(0xFFD99019), 'Amber'),
    'pink': (Color(0xFFD6457A), 'Pink'),
    'red': (Color(0xFFDC4545), 'Red'),
  };

  static Color? of(String? key) => all[key]?.$1;
}

/// The icons an organisation type can have, by the key venue_types.icon
/// keeps.
abstract final class VenueTypeIcons {
  static const fallback = 'fitness';

  static const all = <String, (IconData, String)>{
    'fitness': (Icons.fitness_center_rounded, 'Weights'),
    'run': (Icons.directions_run_rounded, 'Running'),
    'pool': (Icons.pool_rounded, 'Swimming'),
    'cycling': (Icons.directions_bike_rounded, 'Cycling'),
    'sports': (Icons.sports_soccer_rounded, 'Football'),
    'basketball': (Icons.sports_basketball_rounded, 'Basketball'),
    'tennis': (Icons.sports_tennis_rounded, 'Racquet sports'),
    'archery': (Icons.track_changes_rounded, 'Archery'),
    'martial_arts': (Icons.sports_martial_arts_rounded, 'Martial arts'),
    'wellness': (Icons.spa_rounded, 'Spa and wellness'),
    'yoga': (Icons.self_improvement_rounded, 'Yoga and meditation'),
    'hike': (Icons.hiking_rounded, 'Hiking'),
    'climb': (Icons.terrain_rounded, 'Climbing'),
    'golf': (Icons.golf_course_rounded, 'Golf'),
    'health': (Icons.health_and_safety_rounded, 'Health care'),
  };

  static IconData of(String key) => (all[key] ?? all[fallback]!).$1;
}

/// Every service type, in the team's order (then by name); turned-off
/// ones too, for the master. For everyone, signed in or not.
final venueTypesProvider = FutureProvider<List<VenueType>>((ref) => ref.watch(venueRepositoryProvider).types());

/// [key]'s type among [types]; null when it isn't one.
VenueType? venueTypeOf(Iterable<VenueType> types, String key) => types.where((t) => t.key == key).firstOrNull;

/// [key]'s name among [types], or the key tidied ('fitness_centre' ->
/// 'Fitness centre') while they load.
String venueTypeName(Iterable<VenueType> types, String key) =>
    venueTypeOf(types, key)?.name ?? (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' '));
