import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../widgets/form_fields.dart';
import 'opening_hours.dart';

/// Opening hours, day by day: closed, open once, or open twice with a break
/// between (6–10 am, 4–9 pm). [value] null: not given.
class OpeningHoursEditor extends StatelessWidget {
  final OpeningHours? value;
  final ValueChanged<OpeningHours?> onChanged;

  const OpeningHoursEditor({super.key, required this.value, required this.onChanged});

  void _set(int day, List<OpenPeriod> periods) => onChanged(OpeningHours({...value!.days, day: periods}));

  /// One opening time split in two: 6 am–9 pm becomes 6–10 am and 4–9 pm;
  /// otherwise an hour off in the middle.
  static List<OpenPeriod> _withBreak(OpenPeriod p) {
    if (p.open < 600 && p.close > 960) return [OpenPeriod(p.open, 600), OpenPeriod(960, p.close)];
    final mid = (p.open + p.close) ~/ 2;
    return [OpenPeriod(p.open, mid - 30), OpenPeriod(mid + 30, p.close)];
  }

  Future<void> _pick(BuildContext context, int day, int index, {required bool closing}) async {
    final periods = [...?value!.on(day)];
    final p = periods[index];
    final current = closing ? p.close : p.open;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
      helpText: '${OpeningHours.fullNames[day - 1]}: ${closing ? 'closes' : 'opens'} at',
    );
    if (picked == null) return;
    var minutes = picked.hour * 60 + picked.minute;
    if (closing && minutes == 0) minutes = 1440; // closing at midnight
    periods[index] = closing ? OpenPeriod(p.open, minutes) : OpenPeriod(minutes, p.close);
    _set(day, periods);
  }

  /// What's wrong with [day]'s times, if anything.
  static String? problem(List<OpenPeriod>? periods) {
    if (periods == null) return null;
    for (final p in periods) {
      if (p.close <= p.open) return 'Closes before it opens';
    }
    if (periods.length == 2 && periods[1].open <= periods[0].close) return 'The second time must start after the first ends';
    return null;
  }

  /// The whole week is right (the form checks this before saving).
  static bool valid(OpeningHours? hours) => hours == null || hours.days.values.every((p) => problem(p) == null);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hours = value;
    if (hours == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => onChanged(OpeningHours.usual),
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: const Text('Add opening hours'),
        ),
      );
    }
    Widget time(int day, int i, OpenPeriod p) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionChip(label: Text(OpenPeriod.label(p.open)), onPressed: () => _pick(context, day, i, closing: false)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('–')),
            ActionChip(label: Text(OpenPeriod.label(p.close)), onPressed: () => _pick(context, day, i, closing: true)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var day = 1; day <= 7; day++)
          Builder(builder: (context) {
            final periods = hours.on(day) ?? const <OpenPeriod>[];
            final open = periods.isNotEmpty;
            final issue = problem(periods);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(OpeningHours.fullNames[day - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Switch(
                        value: open,
                        onChanged: (on) => _set(day, on ? [const OpenPeriod(360, 1260)] : const []),
                      ),
                      if (!open) Text('Closed', style: TextStyle(color: brand.muted)),
                      for (final (i, p) in periods.indexed) time(day, i, p),
                      if (periods.length == 1)
                        TextButton(
                          onPressed: () => _set(day, _withBreak(periods[0])),
                          child: const Text('Add a break'),
                        )
                      else if (periods.length == 2)
                        TextButton(
                          onPressed: () => _set(day, [OpenPeriod(periods[0].open, periods[1].close)]),
                          child: const Text('No break'),
                        ),
                    ],
                  ),
                  if (issue != null) Text(issue, style: TextStyle(color: brand.danger, fontSize: 12.5)),
                ],
              ),
            );
          }),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => onChanged(OpeningHours({for (var d = 1; d <= 7; d++) d: [...?hours.on(1)]})),
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text("Monday's hours for every day"),
            ),
            TextButton(onPressed: () => onChanged(null), child: const Text('Remove opening hours')),
          ],
        ),
      ],
    );
  }
}

/// What a venue has: the kind's usual facilities as ticks ([suggestions]),
/// and any others it types in.
class FacilitiesEditor extends StatefulWidget {
  final List<String> value;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  const FacilitiesEditor({super.key, required this.value, required this.onChanged, this.suggestions = const []});

  @override
  State<FacilitiesEditor> createState() => _FacilitiesEditorState();
}

class _FacilitiesEditorState extends State<FacilitiesEditor> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  bool _has(String f) => widget.value.any((v) => v.toLowerCase() == f.toLowerCase());

  void _toggle(String f, bool on) =>
      widget.onChanged(on ? [...widget.value, f] : widget.value.where((v) => v.toLowerCase() != f.toLowerCase()).toList());

  void _add() {
    final f = _other.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (f.length < 2 || f.length > 40 || _has(f) || widget.value.length >= 40) return;
    widget.onChanged([...widget.value, f]);
    _other.clear();
  }

  @override
  Widget build(BuildContext context) {
    final own = widget.value.where((v) => !widget.suggestions.any((s) => s.toLowerCase() == v.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in widget.suggestions) FilterChip(label: Text(f), selected: _has(f), onSelected: (on) => _toggle(f, on)),
            for (final f in own) InputChip(label: Text(f), selected: true, onDeleted: () => _toggle(f, false)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _other,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Something else you offer', hintText: 'e.g. Physiotherapy', counterText: ''),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _add, child: const Text('Add')),
          ],
        ),
      ],
    );
  }
}

/// A YouTube or Facebook video address (what the database accepts).
bool isVideoLink(String url) =>
    RegExp(r'^https://([a-z0-9-]+\.)?(youtube\.com|youtu\.be|facebook\.com|fb\.watch)/', caseSensitive: false)
        .hasMatch(url.trim());

/// Video links, YouTube or Facebook: up to 10.
class VideoLinksEditor extends StatefulWidget {
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  const VideoLinksEditor({super.key, required this.value, required this.onChanged});

  @override
  State<VideoLinksEditor> createState() => _VideoLinksEditorState();
}

class _VideoLinksEditorState extends State<VideoLinksEditor> {
  final _link = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _add() {
    final url = _link.text.trim();
    if (!isVideoLink(url)) {
      setState(() => _problem = 'Paste a YouTube or Facebook video link (https://...)');
      return;
    }
    if (widget.value.length >= 10 || widget.value.contains(url)) return;
    widget.onChanged([...widget.value, url]);
    _link.clear();
    setState(() => _problem = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final url in widget.value)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline_rounded),
            title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove video',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => widget.onChanged(widget.value.where((v) => v != url).toList()),
            ),
          ),
        if (widget.value.length < 10)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Video link',
                    hintText: 'https://www.youtube.com/watch?v=...',
                    errorText: _problem,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 4), child: OutlinedButton(onPressed: _add, child: const Text('Add'))),
            ],
          ),
        const FormHint('Post the video on YouTube or Facebook first, then paste its link here. Up to 10.'),
      ],
    );
  }
}
