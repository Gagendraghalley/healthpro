import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../theme/brand.dart';
import '../utils/bhutan_time.dart';
import '../utils/launch.dart';
import '../widgets/common.dart';
import '../widgets/loader.dart';
import 'opening_hours.dart';
import 'venue.dart';
import 'venue_repository.dart';

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

/// The venue's promotional video (its own short clip), under [title];
/// nothing when it has none.
class VenuePromoVideo extends ConsumerWidget {
  final Venue venue;
  final String title;

  const VenuePromoVideo({super.key, required this.venue, this.title = 'Watch'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (venue.promoVideo == null) return const SizedBox.shrink();
    final url = ref.watch(venueRepositoryProvider).promoVideoUrl(venue.promoVideo);
    if (url == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(title),
        PromoVideoPlayer(key: ValueKey(url), url: url),
      ],
    );
  }
}

/// Prepares a still preview from the opening video frame, then plays inline.
/// The landscape viewport stays the same size for portrait and landscape clips.
class PromoVideoPlayer extends StatefulWidget {
  final String url;

  const PromoVideoPlayer({super.key, required this.url});

  @override
  State<PromoVideoPlayer> createState() => _PromoVideoPlayerState();
}

class _PromoVideoPlayerState extends State<PromoVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() {
      _controller = controller;
      _failed = false;
    });
    try {
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      if (!mounted || _controller != controller) {
        await controller.dispose();
        return;
      }
      controller.addListener(_changed);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      await controller.dispose();
      setState(() {
        _controller = null;
        _failed = true;
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      // Finished: from the start again.
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: double.infinity,
          child: AspectRatio(
            // Keep the player landscape at every stage. Portrait video is
            // letterboxed within this frame so the full clip remains visible.
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Semantics(
                button: true,
                label: playing ? 'Pause video' : 'Play video',
                child: InkWell(
                  onTap: c == null || _failed ? _initialize : _toggle,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF172846), Color(0xFF080F1E)],
                          ),
                        ),
                      ),
                      if (ready)
                        FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                        ),
                      if (c != null && !ready)
                        const Center(child: HealthProLoader(size: 44, semanticsLabel: 'Loading video'))
                      else if (!playing)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: .28),
                                      blurRadius: 22,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.play_arrow_rounded, size: 42, color: context.colors.primary),
                              ),
                              if (_failed) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  "The video couldn't be played. Tap to try again.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (ready)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: VideoProgressIndicator(
                            c,
                            allowScrubbing: true,
                            padding: const EdgeInsets.only(top: 12),
                            colors: VideoProgressColors(
                              playedColor: context.colors.primary,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
