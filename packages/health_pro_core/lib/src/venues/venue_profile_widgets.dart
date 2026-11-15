import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../utils/bhutan_time.dart';
import '../utils/launch.dart';
import '../widgets/common.dart';
import 'opening_hours.dart';
import 'venue.dart';

/// 'Open now · until 9 pm', green; 'Closed · opens 4 pm', muted. Nothing
/// when the venue hasn't said its hours for today.
class OpenNowChip extends StatelessWidget {
  final OpeningHours? hours;

  /// Bhutan wall-clock time; now, unless given (tests).
  final DateTime? at;

  const OpenNowChip({super.key, required this.hours, this.at});

  @override
  Widget build(BuildContext context) {
    final now = hours?.at(at ?? BhutanTime.now());
    if (now == null) return const SizedBox.shrink();
    final brand = context.brand;
    return StatusChip(
      label: now.label,
      color: now.open ? brand.success : brand.muted,
      icon: now.open ? Icons.schedule_rounded : Icons.do_not_disturb_on_outlined,
    );
  }
}

/// The week's opening hours, today's marked, days with the same hours
/// together.
class OpeningHoursView extends StatelessWidget {
  final OpeningHours hours;
  final DateTime? at;

  const OpeningHoursView({super.key, required this.hours, this.at});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final today = (at ?? BhutanTime.now()).weekday;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OpenNowChip(hours: hours, at: at),
          const SizedBox(height: 10),
          for (var day = 1; day <= 7; day++)
            if (hours.textOn(day) case final text?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        OpeningHours.fullNames[day - 1],
                        style: TextStyle(fontWeight: day == today ? FontWeight.w800 : FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontWeight: day == today ? FontWeight.w800 : FontWeight.w500,
                          color: text == 'Closed' ? brand.muted : null,
                        ),
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

/// What a venue has: shower, massage... as ticks.
class FacilitiesView extends StatelessWidget {
  final List<String> facilities;

  const FacilitiesView({super.key, required this.facilities});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in facilities)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: brand.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: brand.success),
                const SizedBox(width: 6),
                Text(f, style: TextStyle(color: brand.readable(brand.success), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A YouTube video's id in [url], for its picture; null for others.
String? youTubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return null;
  final host = u.host.toLowerCase();
  if (host.endsWith('youtu.be')) return u.pathSegments.firstOrNull;
  if (host.endsWith('youtube.com')) {
    if (u.queryParameters['v'] case final v?) return v;
    final s = u.pathSegments;
    if (s.length >= 2 && (s[0] == 'shorts' || s[0] == 'embed' || s[0] == 'live')) return s[1];
  }
  return null;
}

/// A venue's videos (YouTube, Facebook): a picture each that opens the video.
class VenueVideosView extends StatelessWidget {
  final List<String> videos;

  const VenueVideosView({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final url in videos)
          Semantics(
            button: true,
            label: 'Play video',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => openExternal(context, Uri.parse(url)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 240,
                  height: 135,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (youTubeId(url) case final id?)
                        Image.network('https://img.youtube.com/vi/$id/hqdefault.jpg',
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: brand.surfaceAlt))
                      else
                        DecoratedBox(
                          decoration: const BoxDecoration(color: Color(0xFF1877F2)),
                          child: Center(
                            child: Text('Facebook video',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
                          ),
                        ),
                      const ColoredBox(color: Color(0x33000000)),
                      const Center(child: Icon(Icons.play_circle_fill_rounded, size: 56, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Who to ask for, and how: the contact person, phone, WhatsApp, email.
class VenueContactDetails extends StatelessWidget {
  final Venue venue;

  const VenueContactDetails({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (venue.contactPerson != null) InfoRow(icon: Icons.person_outline_rounded, text: 'Ask for ${venue.contactPerson}'),
        if (venue.phone != null)
          InkWell(onTap: () => callPhone(context, venue.phone!), child: InfoRow(icon: Icons.call_outlined, text: venue.phone!)),
        if (venue.email != null)
          InkWell(
            onTap: () => openExternal(context, Uri(scheme: 'mailto', path: venue.email)),
            child: InfoRow(icon: Icons.mail_outline_rounded, text: venue.email!),
          ),
      ],
    );
  }
}
