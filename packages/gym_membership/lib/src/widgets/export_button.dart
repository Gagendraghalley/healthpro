import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// 'Export to Excel': [load] gets everything from the database as a sheet,
/// saved as [fileName] (a download in a browser, the share sheet on a
/// phone). [compact]: the icon alone, for an app bar.
class ExportButton extends StatefulWidget {
  final String fileName;
  final Future<Spreadsheet> Function() load;
  final String label;
  final bool compact;

  const ExportButton({
    super.key,
    required this.fileName,
    required this.load,
    this.label = 'Export to Excel',
    this.compact = false,
  });

  @override
  State<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final sheet = await widget.load();
      if (!mounted) return;
      if (sheet.rows.isEmpty) {
        showFeedback(context, 'Nothing to export');
        return;
      }
      final name = safeFileName(widget.fileName.endsWith('.xlsx') ? widget.fileName : '${widget.fileName}.xlsx');
      await saveFile(context, sheet.toXlsx(), name: name, mimeType: Spreadsheet.mimeType);
      if (mounted && kIsWeb) showFeedback(context, '${sheet.rows.length} ${sheet.rows.length == 1 ? 'row' : 'rows'} exported');
    } catch (e) {
      if (mounted) showFeedback(context, friendlyError(e), problem: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.file_download_outlined, size: 20);
    if (widget.compact) {
      return IconButton(tooltip: widget.label, onPressed: _busy ? null : _export, icon: icon);
    }
    return OutlinedButton.icon(onPressed: _busy ? null : _export, icon: icon, label: Text(widget.label));
  }
}
