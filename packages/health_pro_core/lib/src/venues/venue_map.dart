import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/brand.dart';
import '../utils/launch.dart';
import '../widgets/feedback.dart';

/// Thimphu's centre: where a map starts when a venue has no place yet.
const thimphu = LatLng(27.4728, 89.6390);

/// Kilometres between two places, as the crow flies.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// '850 m', '4.2 km', '38 km'.
String distanceText(double km) =>
    km < 1 ? '${(km * 1000 / 50).round() * 50} m' : km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';

/// Where the phone is, after asking to see it. Throws a [StateError] with
/// what to do when it can't (location off, or not allowed).
Future<LatLng> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Turn on location on your phone, then try again.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw StateError('Allow Health Pro to see your location (in your browser or phone settings), then try again.');
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
  );
  return LatLng(p.latitude, p.longitude);
}

/// Where the person said they are this session (Near me), kept so the list
/// of gyms doesn't ask again.
final myLocationProvider = StateProvider<LatLng?>((ref) => null);

/// OpenStreetMap's tiles, with the app's name as their policy asks. Tests
/// switch them off ([showTiles]): they can't reach the internet.
abstract final class MapTiles {
  static bool showTiles = true;

  static Widget layer() => showTiles
      ? TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'bt.healthpro.app')
      : const SizedBox.shrink();

  static Widget attribution() => RichAttributionWidget(
        alignment: AttributionAlignment.bottomRight,
        attributions: [
          TextSourceAttribution('OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), webOnlyWindowName: '_blank')),
        ],
      );
}

/// A pin on the map.
Marker _pin(LatLng at, Color color) => Marker(
      point: at,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: Icon(Icons.location_on_rounded, size: 44, color: color, shadows: const [Shadow(blurRadius: 6, color: Color(0x55000000))]),
    );

/// A small map of a venue's place, with nearby roads, and Directions.
class VenueMap extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double height;

  const VenueMap({super.key, required this.latitude, required this.longitude, this.height = 220});

  @override
  Widget build(BuildContext context) {
    final at = LatLng(latitude, longitude);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: height,
            child: Semantics(
              label: 'Map of where it is',
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: at,
                  initialZoom: 15.5,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  MapTiles.layer(),
                  MarkerLayer(markers: [_pin(at, context.brand.accent)]),
                  MapTiles.attribution(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => openDirections(context, latitude, longitude),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('Directions'),
            ),
            OutlinedButton.icon(
              onPressed: () => openExternal(
                  context, Uri.parse('https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=17/$latitude/$longitude')),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Bigger map'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Choosing a venue's place: tap the map where it is, or use where you
/// stand. [value] null: not chosen.
class LocationPicker extends StatefulWidget {
  final LatLng? value;
  final ValueChanged<LatLng?> onChanged;

  const LocationPicker({super.key, required this.value, required this.onChanged});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final _map = MapController();
  bool _finding = false;

  Future<void> _here() async {
    setState(() => _finding = true);
    await runAction(context, () async {
      final at = await currentLocation();
      widget.onChanged(at);
      _map.move(at, 17);
    });
    if (mounted) setState(() => _finding = false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 260,
            child: Semantics(
              label: 'Map: tap where it is',
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: value ?? thimphu,
                  initialZoom: value == null ? 12 : 16,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onTap: (_, at) => widget.onChanged(at),
                ),
                children: [
                  MapTiles.layer(),
                  if (value != null) MarkerLayer(markers: [_pin(value, brand.accent)]),
                  MapTiles.attribution(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value == null
              ? 'Tap the map at your entrance, so people find you and see you under Near me.'
              : 'Pinned at ${value.latitude.toStringAsFixed(5)}, ${value.longitude.toStringAsFixed(5)}. Tap elsewhere to move it.',
          style: TextStyle(color: brand.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _finding ? null : _here,
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: Text(_finding ? 'Finding you…' : "Use where I'm standing"),
            ),
            if (value != null)
              TextButton(onPressed: () => widget.onChanged(null), child: const Text('Remove the pin')),
          ],
        ),
      ],
    );
  }
}
