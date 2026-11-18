import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_repository.dart';
import '../data/receipts.dart';
import 'member_card.dart' show cardPicture;

/// Opens [paymentId]'s receipt: the paper, and printing it (on the
/// website), saving or sharing its picture, and (for the gym's staff,
/// not [forMember]) sending it to the member on WhatsApp.
Future<void> showReceipt(BuildContext context, String paymentId, {bool forMember = false}) => showAppDialog<void>(
    context: context, builder: (_) => ReceiptDialog(paymentId: paymentId, forMember: forMember));

class ReceiptDialog extends ConsumerStatefulWidget {
  final String paymentId;

  /// The member's own receipt: no WhatsApp to themselves.
  final bool forMember;

  const ReceiptDialog({super.key, required this.paymentId, this.forMember = false});

  @override
  ConsumerState<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends ConsumerState<ReceiptDialog> {
  final _paper = GlobalKey();
  bool _busy = false;

  Future<void> _picture(Receipt r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await cardPicture(_paper);
      if (!mounted) return;
      await saveFile(context, png, name: r.fileName, mimeType: 'image/png');
      if (mounted && kIsWeb) showFeedback(context, 'Receipt saved');
    } catch (e) {
      if (mounted) showFeedback(context, friendlyError(e), problem: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _print(Receipt r) {
    try {
      PagePrinter.printHtml(r.html);
    } catch (e) {
      showFeedback(context, friendlyError(e), problem: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = ref.watch(gymReceiptProvider(widget.paymentId));
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: SizedBox(
        width: 420,
        child: AsyncValueView<Receipt>(
          value: receipt,
          onRetry: () => ref.invalidate(gymReceiptProvider(widget.paymentId)),
          data: (r) => SingleChildScrollView(
            child: RepaintBoundary(key: _paper, child: ReceiptPaper(receipt: r)),
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        if (receipt.valueOrNull case final r?) ...[
          if (PagePrinter.available)
            TextButton.icon(
              onPressed: () => _print(r),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print'),
            ),
          TextButton.icon(
            onPressed: _busy ? null : () => _picture(r),
            icon: Icon(kIsWeb ? Icons.download_rounded : Icons.ios_share_rounded, size: 18),
            label: Text(kIsWeb ? 'Save picture' : 'Share'),
          ),
          if (r.memberPhone != null && !widget.forMember)
            TextButton.icon(
              onPressed: () => openWhatsApp(context, r.memberPhone!, message: r.message),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
        ],
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// The receipt as paper: always white with dark ink, whatever the app's
/// theme, so its picture prints and reads like one.
class ReceiptPaper extends StatelessWidget {
  final Receipt receipt;

  const ReceiptPaper({super.key, required this.receipt});

  static const _ink = Color(0xFF0B1530);
  static const _muted = Color(0xFF5B6478);
  static const _line = Color(0xFFD8DEE9);

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final contact = [r.gymAddress, r.gymPhone, r.gymEmail].whereType<String>().join(' · ');
    const label = TextStyle(color: _muted, fontSize: 13.5, height: 1.35);
    const value = TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: _ink, fontSize: 13.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(r.gymName, style: const TextStyle(color: _ink, fontSize: 19, fontWeight: FontWeight.w800)),
            if (contact.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(contact, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _ink, width: 2), bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('RECEIPT ${r.number}',
                        style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                  ),
                  Text(formatMoment(r.paidAt), style: const TextStyle(color: _muted, fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final (l, v) in r.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 118, child: Text(l, style: label)),
                    Expanded(child: Text(v, style: value)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _ink, width: 2))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: Text('Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Text(formatNu(r.amount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            if (r.isRefunded)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Refunded', style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 16),
            const Text('Thank you!  ·  Health Pro',
                textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// A small 'Receipt' button: opens [paymentId]'s receipt.
class ReceiptButton extends StatelessWidget {
  final String paymentId;

  const ReceiptButton({super.key, required this.paymentId});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Receipt',
        icon: const Icon(Icons.receipt_long_outlined),
        onPressed: () => showReceipt(context, paymentId),
      );
}
