import 'package:flutter/widgets.dart';

/// The query parameter a link to a list page names one of its records by:
/// `/gyms/<id>/manage/classes?open=<classId>` (the search's results).
const openParam = 'open';

/// [path] with `?open=[id]` (none for a null [id]).
String withOpen(String path, String? id) =>
    id == null ? path : '$path${path.contains('?') ? '&' : '?'}$openParam=${Uri.encodeQueryComponent(id)}';

/// Opens the record a link asks for ([id], from `?open=`) once its list has
/// loaded: [open] shows it the way its Open button does. Once for each id,
/// so saving it (which loads the list again) doesn't open it again; an id
/// that isn't in the list opens nothing.
class OpenFromLink<T> extends StatefulWidget {
  final String? id;

  /// The page's records; null while they load.
  final List<T>? items;
  final String Function(T item) idOf;
  final void Function(T item) open;
  final Widget child;

  const OpenFromLink({
    super.key,
    required this.id,
    required this.items,
    required this.idOf,
    required this.open,
    required this.child,
  });

  @override
  State<OpenFromLink<T>> createState() => _OpenFromLinkState<T>();
}

class _OpenFromLinkState<T> extends State<OpenFromLink<T>> {
  /// The id last looked for.
  String? _done;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant OpenFromLink<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  void _check() {
    final id = widget.id;
    final items = widget.items;
    if (id == null || id == _done || items == null) return;
    _done = id;
    for (final item in items) {
      if (widget.idOf(item) != id) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.open(item);
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
