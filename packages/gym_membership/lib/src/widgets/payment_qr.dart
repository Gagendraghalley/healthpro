import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/online_payments.dart';

/// The QR code to pay a gym with, made from its bank account when someone
/// pays: the code, how much, and the account written out (with Copy) for
/// typing it into a bank app. The same for the member (Pay online) and at
/// the front desk.
class PaymentQrCard extends StatelessWidget {
  final PaymentAccount account;
  final String qrImageUrl;

  /// Ngultrum; null or 0 leaves the amount out.
  final int? amount;

  /// What it's for: 'Peak Fitness, Monthly'.
  final String? note;

  final double size;

  const PaymentQrCard(
      {super.key,
      required this.account,
      required this.qrImageUrl,
      this.amount,
      this.note,
      this.size = 220});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const ink = Color(0xFF0B1530);
    final pays = amount != null && amount! > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: brand.cardShadow),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                qrImageUrl,
                width: size,
                height: size,
                fit: BoxFit.contain,
                semanticLabel:
                    'Bank-issued payment QR code for ${account.accountName}',
                errorBuilder: (_, __, ___) => SizedBox(
                    width: size,
                    height: size,
                    child:
                        const Center(child: Icon(Icons.broken_image_outlined))),
              ),
              if (pays) ...[
                const SizedBox(height: 10),
                Text(formatNu(amount!),
                    style: const TextStyle(
                        color: ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: brandFont)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(account.accountName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(account.bankName,
            textAlign: TextAlign.center, style: TextStyle(color: brand.muted)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(
                account.spacedNumber,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: 1,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            IconButton(
              tooltip: 'Copy the account number',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: account.accountNumber));
                if (context.mounted) {
                  showFeedback(context, 'Account number copied');
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// At the front desk: the gym's payment QR code for [amount], held up for
/// the member to scan with their bank app.
Future<void> showPaymentQr(BuildContext context,
    {required PaymentAccount account,
    required String qrImageUrl,
    int? amount,
    String? note}) {
  return showAppDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Scan to pay'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PaymentQrCard(
                  account: account,
                  qrImageUrl: qrImageUrl,
                  amount: amount,
                  note: note),
              const SizedBox(height: 12),
              Text(
                'They pay in their bank app, then show the receipt: enter its journal number below the amount.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.brand.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('Done'))
      ],
    ),
  );
}
