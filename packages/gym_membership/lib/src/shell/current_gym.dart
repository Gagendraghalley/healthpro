import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';

/// The gyms the signed-in person works at, by name: every organisation this
/// module runs (a pool or a wellness centre is run like a gym).
final myGymsProvider = Provider<AsyncValue<List<MyVenue>>>(
  (ref) => ref.watch(myVenuesProvider).whenData((all) => [
        for (final v in all)
          if (gymModuleRuns(v.venue)) v,
      ]),
);

/// The gym last opened, so the menu and Home stay on it while they visit
/// their account or notifications.
final rememberedGymProvider = StateProvider<String?>((ref) => null);

/// The gym being worked at: the one in [pathGymId] (the page's address),
/// else the one last opened, else the first.
MyVenue? currentGym(List<MyVenue> gyms, {String? pathGymId, String? remembered}) {
  if (gyms.isEmpty) return null;
  MyVenue? find(String? id) => id == null ? null : gyms.where((g) => g.venue.id == id).firstOrNull;
  return find(pathGymId) ?? find(remembered) ?? gyms.first;
}
