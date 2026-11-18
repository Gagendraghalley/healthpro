import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/page_actions.dart';
import 'admin_repository.dart';

/// Admin -> App errors: what went wrong in the app on people's phones and in
/// their browsers (release builds send them; see ErrorReporter), the latest
/// first. Each row is one kind of error with how often it happened; open one
/// for where and the stack, and clear it once it's put right.
class AdminErrorsScreen extends ConsumerWidget {
  const AdminErrorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'App errors',
      permission: PlatformPermission.errors,
      builder: (context, _) => AppPage(
        title: 'App errors',
        body: AsyncValueView<List<AppError>>(
          value: ref.watch(appErrorsProvider),
          onRetry: () => ref.invalidate(appErrorsProvider),
          data: (errors) => ListView(
            padding: pagePadding(context),
            children: [
              PageActions(
                text: 'Errors the app hit on people\'s phones and browsers. The same error is one row with a count. '
                    'Clear one once it\'s fixed; it comes back if it happens again. Kept 90 days.',
                bottom: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(appErrorsProvider),
                    style: OutlinedButton.styleFrom(minimumSize: PageActions.buttonSize),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              if (errors.isEmpty)
                const EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No errors',
                  message: 'Nothing has gone wrong in the app lately.',
                )
              else
                _ErrorsTable(errors: errors),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorsTable extends ConsumerWidget {
  final List<AppError> errors;

  const _ErrorsTable({required this.errors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return DataGrid<AppError>(
      rows: errors,
      noun: 'errors',
      rowLabel: (e) => 'Open: ${e.message}',
      onRowTap: (e) => showDialog<void>(context: context, builder: (_) => _ErrorDialog(error: e)),
      columns: [
        GridColumn(
          key: 'error',
          label: 'Error',
          flex: 5,
          sortBy: (e) => e.message.toLowerCase(),
          cell: (context, e) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.message,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
              if (!DataGrid.shows(context, 'page') && e.page != null)
                Text(e.page!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
            ],
          ),
        ),
        GridColumn(
          key: 'page',
          label: 'Page',
          flex: 2,
          showFrom: 760,
          sortBy: (e) => e.page ?? '',
          cell: (context, e) =>
              Text(e.page ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'platform',
          label: 'On',
          width: 96,
          showFrom: 560,
          sortBy: (e) => e.platform ?? '',
          cell: (context, e) => Text(platformLabel(e.platform), style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'times',
          label: 'Times',
          width: 80,
          alignEnd: true,
          sortBy: (e) => -e.times,
          cell: (context, e) => StatusChip(label: '${e.times}×', color: e.times >= 10 ? brand.danger : brand.muted),
        ),
        GridColumn(
          key: 'last',
          label: 'Last seen',
          width: 128,
          showFrom: 440,
          alignEnd: true,
          sortBy: (e) => -e.lastSeen.millisecondsSinceEpoch,
          cell: (context, e) => Text(timeAgo(e.lastSeen), style: TextStyle(color: brand.muted)),
        ),
        GridColumn.actions(
          cell: (context, e) =>
              GridOpenButton(onPressed: () => showDialog<void>(context: context, builder: (_) => _ErrorDialog(error: e))),
        ),
      ],
    );
  }
}

/// 'web' -> 'Web', 'android' -> 'Android', 'iOS' as it is.
String platformLabel(String? platform) => switch (platform) {
      null || '' => '—',
      'web' => 'Web',
      'android' => 'Android',
      final other => other,
    };

/// One error in full: the message, where and when, the stack to copy, and
/// clearing it.
class _ErrorDialog extends ConsumerWidget {
  final AppError error;

  const _ErrorDialog({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final e = error;
    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label  ', style: TextStyle(color: brand.muted, fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: TextStyle(color: brand.body)),
          ])),
        );
    final everything = [
      e.message,
      if (e.page != null) 'Page: ${e.page}',
      'On: ${platformLabel(e.platform)}',
      '${e.times} times, ${formatMoment(e.firstSeen)} to ${formatMoment(e.lastSeen)}',
      if (e.stack != null) '\n${e.stack}',
    ].join('\n');

    Future<void> clear() async {
      final done = await runAction(
        context,
        () => ref.read(adminRepositoryProvider).clearAppError(e.id),
        success: 'Cleared',
      );
      if (!done) return;
      ref.invalidate(appErrorsProvider);
      if (context.mounted) Navigator.of(context).pop();
    }

    return AlertDialog(
      title: const Text('App error'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(e.message, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink, height: 1.35)),
              const SizedBox(height: 14),
              fact('Page', e.page ?? '—'),
              fact('On', platformLabel(e.platform)),
              fact('Times', '${e.times}'),
              fact('First seen', formatMoment(e.firstSeen)),
              fact('Last seen', formatMoment(e.lastSeen)),
              fact('Last hit', e.who),
              if (e.stack != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brand.muted.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    e.stack!,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: brand.body),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: everything));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy'),
        ),
        TextButton(
          onPressed: clear,
          style: TextButton.styleFrom(foregroundColor: brand.danger),
          child: const Text('Clear, it\'s fixed'),
        ),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
