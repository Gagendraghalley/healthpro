import 'package:flutter/material.dart';
import 'package:health_pro_core/health_pro_core.dart';

// A plan's words, laid out to read: each day (or section) a card, each
// exercise a row with its sets and reps, anything else as it was written.

/// One line of a plan: an exercise with its [dose] (sets and reps), a
/// [bullet] point, or words as written.
class PlanLine {
  final String text;
  final String? dose;
  final bool bullet;

  const PlanLine(this.text, {this.dose, this.bullet = false});
}

/// A day (or section) of a plan: 'Day 1' ([label]) 'Legs' ([title]), and its
/// lines. Untitled for words outside any day, such as notes.
class PlanSection {
  final String? label;
  final String? title;
  final List<PlanLine> lines;

  PlanSection({this.label, this.title, List<PlanLine>? lines}) : lines = lines ?? [];

  bool get titled => label != null || title != null;
}

final _bullet = RegExp(r'^(?:[-*•]|\d+[.)])\s+');
/// 'Day 1: Legs', 'Day 3', 'Breakfast - eggs': a heading is followed by a
/// colon, comma or dash, or by nothing ('Warm up for 5 minutes' isn't one).
final _day = RegExp(
    r'^((?:day|week)\s*\d+|monday|tuesday|wednesday|thursday|friday|saturday|sunday|breakfast|lunch|snack|dinner|warm[- ]?up|cool[- ]?down)\s*(?:[:.,–-]\s*(.*))?$',
    caseSensitive: false);
final _doseAfterColon = RegExp(r'^(.*?)\s*[:–]\s*(.*\d.*)$');
final _doseAtEnd = RegExp(r'^(.*?)\s+(\d+\s*[x×]\s*\S.*)$', caseSensitive: false);

/// '4 x 8-10' as '4 × 8–10'.
String prettyDose(String dose) =>
    dose.trim().replaceAll(RegExp(r'\s*[x×]\s*(?=\d)', caseSensitive: false), ' × ').replaceAllMapped(RegExp(r'(\d)\s*-\s*(\d)'), (m) => '${m[1]}–${m[2]}');

/// A plan's words read as sections: 'Day 1: Legs' (or Monday, Breakfast,
/// Warm-up...) starts one; '- Squats: 4 x 8-10' is an exercise and its dose;
/// a blank line ends a section, so words after it stand alone.
List<PlanSection> readPlanText(String content) {
  final sections = <PlanSection>[];
  PlanSection? current;
  PlanSection open() {
    if (current == null) sections.add(current = PlanSection());
    return current!;
  }

  for (final raw in content.split('\n')) {
    final line = raw.replaceAll('**', '').replaceFirst(RegExp(r'^\s*#+\s*'), '').trim();
    if (line.isEmpty) {
      // Ends the section, unless it's a bare heading ('Day 1:') still to be filled.
      if (current != null && (current!.lines.isNotEmpty || current!.title != null)) current = null;
      continue;
    }
    final bulleted = _bullet.hasMatch(line);
    final day = bulleted ? null : _day.firstMatch(line);
    if (day != null) {
      final label = day[1]!.trim();
      final rest = (day[2] ?? '').trim();
      current = PlanSection(label: _capital(label), title: rest.isEmpty ? null : rest);
      sections.add(current!);
      continue;
    }
    if (!bulleted && line.endsWith(':') && line.length <= 60) {
      current = PlanSection(title: line.substring(0, line.length - 1).trim());
      sections.add(current!);
      continue;
    }
    final text = line.replaceFirst(_bullet, '');
    final match = bulleted ? (_doseAfterColon.firstMatch(text) ?? _doseAtEnd.firstMatch(text)) : null;
    open().lines.add(match != null && match[1]!.trim().isNotEmpty
        ? PlanLine(match[1]!.trim(), dose: prettyDose(match[2]!), bullet: true)
        : PlanLine(text, bullet: bulleted));
  }
  // A heading with nothing under it ('Here is the plan:') is left out; a day
  // stays, even empty (a rest day).
  return sections.where((s) => s.label != null || s.lines.isNotEmpty).toList();
}

String _capital(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// ─── The pieces both kinds of plan are laid out with ────────────────────────

/// A day or a meal: a bordered card.
class PlanCard extends StatelessWidget {
  final Widget child;

  const PlanCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          border: Border.all(color: context.brand.muted.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// 'Day 1', 'Breakfast': a card's name, in a filled badge.
class PlanBadge extends StatelessWidget {
  final String label;

  const PlanBadge(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: context.brand.highlight, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      );
}

/// '3 × 8–10', '215 kcal · 4.5 g': numbers in a soft pill, the digits lined up.
class PlanPill extends StatelessWidget {
  final String text;

  const PlanPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: context.brand.highlight.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                color: context.brand.ink, fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
      );
}

/// A row of a card, with a hairline above it when [divided].
class PlanRow extends StatelessWidget {
  final Widget child;
  final bool divided;

  const PlanRow({super.key, required this.child, this.divided = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration:
            divided ? BoxDecoration(border: Border(top: BorderSide(color: context.brand.muted.withValues(alpha: 0.15)))) : null,
        child: child,
      );
}

/// A plan's words laid out to read (see [readPlanText]); they can be selected
/// and copied.
class PlanTextView extends StatelessWidget {
  final String content;

  const PlanTextView({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final sections = readPlanText(content);

    Widget line(PlanLine l, {required bool divided}) => PlanRow(
          divided: divided,
          child: Row(
            children: [
              if (l.bullet && l.dose == null)
                Padding(padding: const EdgeInsets.only(right: 10), child: Icon(Icons.circle, size: 6, color: brand.highlight)),
              Expanded(
                child: Text(l.text,
                    style: TextStyle(color: l.bullet ? brand.ink : brand.body, fontSize: 14.5, height: 1.45,
                        fontWeight: l.dose != null ? FontWeight.w500 : FontWeight.w400)),
              ),
              if (l.dose != null) ...[const SizedBox(width: 12), PlanPill(l.dose!)],
            ],
          ),
        );

    List<Widget> lines(PlanSection s) => [
          for (var i = 0; i < s.lines.length; i++) line(s.lines[i], divided: i > 0 && s.lines[i].dose != null && s.lines[i - 1].dose != null),
        ];

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in sections)
            if (s.titled)
              PlanCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (s.label != null) Padding(padding: const EdgeInsets.only(right: 10), child: PlanBadge(s.label!)),
                        if (s.title != null)
                          Expanded(child: Text(s.title!, style: TextStyle(color: brand.ink, fontSize: 15.5, fontWeight: FontWeight.w700))),
                      ],
                    ),
                    if (s.lines.isNotEmpty) const SizedBox(height: 4),
                    ...lines(s),
                  ],
                ),
              )
            else
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lines(s))),
        ],
      ),
    );
  }
}
