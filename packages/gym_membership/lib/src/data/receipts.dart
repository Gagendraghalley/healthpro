import 'package:health_pro_core/health_pro_core.dart';

/// A payment's receipt (gym_payment_receipt): the gym, the receipt's number
/// and date, who paid, for which package and dates, how much and how, and
/// who took it.
class Receipt {
  final String paymentId;
  final int receiptNo;
  final DateTime paidAt;
  final int amount;
  final PaymentMethod method;
  final String? reference;
  final String status;
  final String gymName;
  final String? gymPhone;
  final String? gymEmail;
  final String? gymAddress;
  final String memberName;
  final String? memberCode;
  final String? memberPhone;
  final String? planName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? receivedBy;

  /// The package's full price, when they paid less; the offer and why.
  final int? listPrice;
  final String? offerName;
  final String? discountReason;

  const Receipt({
    required this.paymentId,
    required this.receiptNo,
    required this.paidAt,
    required this.amount,
    required this.method,
    required this.status,
    required this.gymName,
    required this.memberName,
    this.reference,
    this.gymPhone,
    this.gymEmail,
    this.gymAddress,
    this.memberCode,
    this.memberPhone,
    this.planName,
    this.startDate,
    this.endDate,
    this.receivedBy,
    this.listPrice,
    this.offerName,
    this.discountReason,
  });

  bool get isRefunded => status == 'refunded';

  /// '- Nu. 450 (Student)', when they paid less than the full price.
  String? get discountLine {
    if (listPrice == null || listPrice! <= amount) return null;
    final why = [offerName, discountReason].whereType<String>().join(': ');
    return '- ${formatNu(listPrice! - amount)}${why.isEmpty ? '' : ' ($why)'}';
  }

  /// 'No. 000012'.
  String get number => 'No. ${receiptNumber(receiptNo)}';

  /// 'JRN 123456789' for a bank or mBoB payment; 'Ref ...' for another kind.
  String? get referenceLine => reference == null
      ? null
      : (method == PaymentMethod.mbob || method == PaymentMethod.bank ? 'JRN $reference' : 'Ref $reference');

  /// '8 Nov 2026 to 8 Feb 2027'.
  String? get period =>
      startDate == null || endDate == null ? null : '${formatDate(startDate!)} to ${formatDate(endDate!)}';

  /// The paper's lines, label and value, in order (the picture, the printed
  /// page and the message all show these).
  List<(String, String)> get lines => [
        ('Received from', memberName),
        if (memberCode != null) ('Member code', memberCode!),
        if (planName != null) ('Package', planName!),
        if (period != null) ('Valid', period!),
        if (discountLine != null) ...[('Full price', formatNu(listPrice!)), ('Discount', discountLine!)],
        ('Paid by', method.label),
        if (referenceLine != null) ('Reference', referenceLine!),
        if (receivedBy != null) ('Received by', receivedBy!),
      ];

  /// The file the picture is saved as.
  String get fileName => safeFileName('$gymName receipt ${receiptNumber(receiptNo)}.png');

  factory Receipt.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => json[key] == null ? null : BhutanTime.parseDate(json[key] as String);
    String? text(String key) {
      final v = (json[key] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return Receipt(
      paymentId: json['payment_id'] as String,
      receiptNo: (json['receipt_no'] as num).toInt(),
      paidAt: DateTime.parse(json['paid_at'] as String),
      amount: (json['amount'] as num).toInt(),
      method: PaymentMethod.from(json['method'] as String),
      reference: text('reference'),
      status: json['status'] as String? ?? 'completed',
      gymName: json['gym_name'] as String,
      gymPhone: text('gym_phone'),
      gymEmail: text('gym_email'),
      gymAddress: text('gym_address'),
      memberName: text('member_name') ?? 'Member',
      memberCode: text('member_code'),
      memberPhone: text('member_phone'),
      planName: text('plan_name'),
      startDate: date('start_date'),
      endDate: date('end_date'),
      receivedBy: text('received_by'),
      listPrice: (json['list_price'] as num?)?.toInt(),
      offerName: text('offer_name'),
      discountReason: text('discount_reason'),
    );
  }

  /// The receipt as a WhatsApp message.
  String get message => [
        '*$gymName*',
        'Receipt $number · ${formatMoment(paidAt)}',
        '',
        for (final (label, value) in lines) '$label: $value',
        'Amount: *${formatNu(amount)}*${isRefunded ? ' (refunded)' : ''}',
        '',
        'Thank you!',
      ].join('\n');

  /// The receipt as a page to print: the paper's lines, in plain HTML.
  String get html {
    String e(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    final contact = [gymAddress, gymPhone, gymEmail].whereType<String>().map(e).join(' · ');
    final rows = [for (final (label, value) in lines) '<tr><th>${e(label)}</th><td>${e(value)}</td></tr>'].join();
    return '''<!doctype html><html><head><meta charset="utf-8"><title>${e('$gymName receipt $number')}</title>
<style>
  body { font-family: -apple-system, "Segoe UI", Roboto, Arial, sans-serif; color: #0B1530; margin: 0; }
  .paper { max-width: 420px; margin: 24px auto; padding: 24px; border: 1px solid #D8DEE9; border-radius: 12px; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .contact { color: #5B6478; font-size: 12px; margin-bottom: 16px; }
  .title { display: flex; justify-content: space-between; font-weight: 700; border-top: 2px solid #0B1530;
           border-bottom: 1px solid #D8DEE9; padding: 8px 0; margin-bottom: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th { text-align: left; color: #5B6478; font-weight: 500; padding: 5px 12px 5px 0; vertical-align: top; width: 40%; }
  td { padding: 5px 0; }
  .amount { display: flex; justify-content: space-between; align-items: baseline; border-top: 2px solid #0B1530;
            margin-top: 10px; padding-top: 10px; font-size: 22px; font-weight: 800; }
  .refunded { color: #C62828; font-size: 14px; font-weight: 700; }
  .foot { text-align: center; color: #5B6478; font-size: 12px; margin-top: 18px; }
  @media print { .paper { border: none; margin: 0 auto; } }
</style></head><body><div class="paper">
<h1>${e(gymName)}</h1>${contact.isEmpty ? '' : '<div class="contact">$contact</div>'}
<div class="title"><span>RECEIPT ${e(number)}</span><span>${e(formatMoment(paidAt))}</span></div>
<table>$rows</table>
<div class="amount"><span>Amount</span><span>${e(formatNu(amount))}</span></div>
${isRefunded ? '<div class="refunded">Refunded</div>' : ''}
<div class="foot">Thank you! · Health Pro</div>
</div></body></html>''';
  }
}

/// A receipt number as printed: six digits, '000012'.
String receiptNumber(int n) => n.toString().padLeft(6, '0');

/// One of the member's own receipts at a gym, in a list (my_gyms): its
/// number, what it paid for, how much and when. It opens with [Receipt].
class ReceiptLine {
  final String paymentId;
  final int receiptNo;
  final int amount;
  final PaymentMethod method;
  final bool isRefunded;
  final DateTime paidAt;
  final String? planName;

  const ReceiptLine({
    required this.paymentId,
    required this.receiptNo,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.isRefunded = false,
    this.planName,
  });

  factory ReceiptLine.fromJson(Map<String, dynamic> json) => ReceiptLine(
        paymentId: json['payment_id'] as String,
        receiptNo: (json['receipt_no'] as num).toInt(),
        amount: (json['amount'] as num).toInt(),
        method: PaymentMethod.from(json['method'] as String),
        isRefunded: json['status'] == 'refunded',
        paidAt: DateTime.parse(json['paid_at'] as String),
        planName: json['plan_name'] as String?,
      );
}
