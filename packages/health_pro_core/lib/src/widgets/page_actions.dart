import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// A page's own buttons (Add, Export, Refresh...), at the top of its content
/// under the top bar. The bar keeps only the title, search and the app's own
/// buttons, so it never gets crowded: pages don't pass `actions` to
/// [AppPage].
///
/// [text] (a line about the page) on the left and the buttons on the right;
/// on a phone the text above and the buttons sharing the width, unless
/// [stretch] is false (controls that keep their own size, like a range
/// picker), when they wrap.
class PageActions extends StatelessWidget {
  final String? text;
  final List<Widget> children;
  final bool stretch;

  /// Space under the row, before the page's content.
  final double bottom;

  const PageActions({super.key, this.text, required this.children, this.stretch = true, this.bottom = 16});

  /// The size page buttons use: as tall as the bar's own (40).
  static const buttonSize = Size(0, 40);

  @override
  Widget build(BuildContext context) {
    final note = text == null ? null : Text(text!, style: TextStyle(color: context.brand.muted));
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null) ...[note, const SizedBox(height: 10)],
              if (stretch)
                Row(
                  children: [
                    for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: c)],
                  ],
                )
              else
                Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: note ?? const SizedBox()),
            for (final c in children) ...[const SizedBox(width: 10), c],
          ],
        );
      }),
    );
  }
}
