import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:health_pro_core/health_pro_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/joining.dart';
import '../data/online_payments.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/payment_qr.dart';

// ─── The desk: confirming online payments ─────────────────────────────────

/// Confirms [claim] after the desk has found it in the bank's records: the
/// package starts, and the member is told.
Future<void> confirmPaymentClaim(
    BuildContext context, WidgetRef ref, PaymentClaim claim) async {
  final sure = await confirmAction(
    context,
    title: "Confirm ${claim.memberName}'s payment?",
    message:
        'First find journal number ${claim.jrn} for ${formatNu(claim.amount)} in the bank\'s records. '
        'Confirming starts ${claim.planName} for ${claim.monthsLabel}, and tells them.',
    confirmLabel: 'Confirm payment',
  );
  if (!sure || !context.mounted) return;
  DateTime? end;
  final ok = await runAction(
      context,
      () async =>
          end = await ref.read(gymRepositoryProvider).confirmClaim(claim.id));
  if (!ok || !context.mounted) return;
  refreshGym(ref, claim.venueId);
  ref.invalidate(gymMemberProvider(claim.gymMemberId));
  showFeedback(
      context, 'Confirmed: ${claim.planName} until ${formatDate(end!)}');
}

/// Says the payment couldn't be found, with why for the member.
Future<void> rejectPaymentClaim(
    BuildContext context, WidgetRef ref, PaymentClaim claim) async {
  final note = await askText(
    context,
    title: "Couldn't find it?",
    hint:
        'For ${claim.memberName} (optional): e.g. not in our statement, check the number',
    confirmLabel: 'Tell them',
  );
  if (note == null || !context.mounted) return;
  final ok = await runAction(context,
      () => ref.read(gymRepositoryProvider).rejectClaim(claim.id, note: note),
      success: '${claim.memberName} is told');
  if (ok) refreshGym(ref, claim.venueId);
}

/// An online payment, for the desk: who, what for, how much (against the
/// package's price) and the journal number to look for; and, for those who
/// take payments, Confirm and Not found.
class PaymentClaimCard extends ConsumerWidget {
  final PaymentClaim claim;

  /// They may confirm it (gym.payments).
  final bool canConfirm;

  /// On the member's own page: no need to say who.
  final bool showMember;

  /// In a card; false in the details dialog, which is its own frame.
  final bool framed;

  const PaymentClaimCard(
      {super.key,
      required this.claim,
      required this.canConfirm,
      this.showMember = true,
      this.framed = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final plans = ref
            .watch(gymPlansProvider((venueId: claim.venueId, all: true)))
            .valueOrNull ??
        const <GymPlan>[];
    final plan = plans.where((p) => p.id == claim.planId).firstOrNull;
    final price = plan == null ? null : packagePrice(plan, claim.months);
    final differs = price != null && price != claim.amount;
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded, color: brand.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showMember ? claim.memberName : 'Paid online',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text('Sent ${timeAgo(claim.createdAt)}',
                        style: TextStyle(color: brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Text(formatNu(claim.amount),
                  style: context.text.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(
              icon: Icons.sell_outlined,
              text: '${claim.planName} · ${claim.monthsLabel}'),
          if (differs)
            InfoRow(
                icon: Icons.info_outline_rounded,
                text: 'The price for that is ${formatNu(price)}.'),
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: brand.muted),
              const SizedBox(width: 10),
              Text('JRN ', style: TextStyle(color: brand.muted)),
              Flexible(
                child: SelectableText(claim.jrn,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
              IconButton(
                tooltip: 'Copy the journal number',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: claim.jrn));
                  if (context.mounted) {
                    showFeedback(context, 'Copied ${claim.jrn}');
                  }
                },
              ),
            ],
          ),
          if (claim.isPending && canConfirm) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => confirmPaymentClaim(context, ref, claim),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: () => rejectPaymentClaim(context, ref, claim),
                    child: const Text('Not found')),
              ],
            ),
          ] else if (claim.isPending)
            Text('Someone who takes payments confirms it.',
                style: TextStyle(color: brand.muted, fontSize: 12.5)),
          if (!claim.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                StatusChip(
                  label: claim.status.label,
                  color: claim.status == ClaimStatus.confirmed
                      ? brand.success
                      : brand.danger,
                ),
                if (claim.decisionNote != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(claim.decisionNote!,
                          style: TextStyle(color: brand.muted))),
                ],
              ],
            ),
          ],
        ],
      );
    return framed
        ? SectionCard(padding: const EdgeInsets.all(16), child: body)
        : Padding(padding: const EdgeInsets.all(20), child: body);
  }
}

/// Online payments as a table. Open shows a waiting one (Confirm, Not
/// found); an answered one opens its member.
class _ClaimsTable extends StatelessWidget {
  final List<PaymentClaim> claims;
  final String venueId;
  final bool canConfirm;

  const _ClaimsTable(
      {required this.claims, required this.venueId, required this.canConfirm});

  void _open(BuildContext context, PaymentClaim c) =>
      _openClaim(context, c, venueId: venueId, canConfirm: canConfirm);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final pending = claims.any((c) => c.isPending);
    DateTime when(PaymentClaim c) =>
        c.isPending ? c.createdAt : (c.decidedAt ?? c.createdAt);
    Widget status(PaymentClaim c) => StatusChip(
          label: c.status.label,
          color: c.isPending
              ? brand.warning
              : c.status == ClaimStatus.confirmed
                  ? brand.success
                  : brand.danger,
        );
    return DataGrid<PaymentClaim>(
      rows: claims,
      noun: 'payments',
      rowLabel: (c) => 'Open ${c.memberName}',
      onRowTap: (c) => _open(context, c),
      columns: [
        GridColumn(
          key: 'member',
          label: 'Member',
          flex: 4,
          sortBy: (c) => c.memberName.toLowerCase(),
          cell: (context, c) {
            final carry = [
              if (!DataGrid.shows(context, 'amount')) formatNu(c.amount),
              if (!DataGrid.shows(context, 'package'))
                '${c.planName} · ${c.monthsLabel}',
              if (!DataGrid.shows(context, 'jrn')) 'JRN ${c.jrn}',
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: brand.ink)),
                if (carry.isNotEmpty)
                  Text(carry.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: brand.muted, fontSize: 13)),
                if (!DataGrid.shows(context, 'status'))
                  Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: status(c)),
              ],
            );
          },
        ),
        GridColumn(
          key: 'package',
          label: 'Package',
          flex: 3,
          showFrom: 760,
          sortBy: (c) => c.planName.toLowerCase(),
          cell: (context, c) => Text('${c.planName} · ${c.monthsLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'amount',
          label: 'Amount',
          flex: 2,
          showFrom: 600,
          sortBy: (c) => c.amount,
          cell: (context, c) => Text(formatNu(c.amount),
              style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
        ),
        GridColumn(
          key: 'jrn',
          label: 'JRN',
          flex: 2,
          showFrom: 900,
          sortBy: (c) => c.jrn,
          cell: (context, c) => Text(c.jrn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: brand.body,
                  letterSpacing: 1,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        GridColumn(
          key: 'when',
          label: pending ? 'Sent' : 'Answered',
          flex: 2,
          showFrom: 1040,
          sortBy: when,
          cell: (context, c) =>
              Text(timeAgo(when(c)), style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 130,
          showFrom: 520,
          sortBy: (c) => c.status.index,
          cell: (context, c) => status(c),
        ),
        GridColumn.actions(
            cell: (context, c) =>
                GridOpenButton(onPressed: () => _open(context, c))),
      ],
    );
  }
}

/// Opens a waiting payment (to confirm it, or say it wasn't found), or the
/// member an answered one is for.
void _openClaim(BuildContext context, PaymentClaim c,
    {required String venueId, required bool canConfirm}) {
  if (!c.isPending) {
    context.go(GymRoutes.memberFor(venueId, c.gymMemberId));
    return;
  }
  showRowDetails(
    context,
    title: 'Online payment',
    // Watched, so Confirm or Not found shows straight away.
    builder: (context) => Consumer(builder: (context, ref, _) {
      final now = ref
          .watch(gymPaymentClaimsProvider(venueId))
          .valueOrNull
          ?.where((x) => x.id == c.id)
          .firstOrNull;
      return PaymentClaimCard(
          claim: now ?? c, canConfirm: canConfirm, framed: false);
    }),
  );
}

/// Payments to confirm: members who paid online into the gym's bank account
/// and gave the journal number. The desk checks each with the bank, then
/// confirms it (their package starts) or says it couldn't find it.
class PaymentsToConfirmScreen extends ConsumerWidget {
  final String venueId;

  /// The payment to open (a link's `?open=`).
  final String? openId;

  const PaymentsToConfirmScreen({super.key, required this.venueId, this.openId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Payments to confirm',
      permission: GymPermission.payments,
      builder: (context, access) {
        final claims = ref.watch(gymPaymentClaimsProvider(venueId));
        final settings = ref.watch(gymSettingsProvider(venueId)).valueOrNull;
        return OpenFromLink<PaymentClaim>(
          id: openId,
          items: claims.valueOrNull,
          idOf: (c) => c.id,
          open: (c) => _openClaim(context, c,
              venueId: venueId, canConfirm: access.can(GymPermission.payments)),
          child: AppPage(
          title: 'Payments to confirm',
          body: AsyncValueView<List<PaymentClaim>>(
            value: claims,
            onRetry: () => ref.invalidate(gymPaymentClaimsProvider(venueId)),
            data: (list) {
              final waiting = list.where((c) => c.isPending).toList();
              final answered =
                  list.where((c) => !c.isPending).take(30).toList();
              return RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(gymPaymentClaimsProvider(venueId).future),
                child: ListView(
                  padding: pagePadding(context),
                  children: [
                    FadeSlideIn(
                      child: WelcomeBand(
                        eyebrow: access.venue.name,
                        title: 'Payments to confirm',
                        subtitle: waiting.isEmpty
                            ? 'Nothing waiting. Online payments wait here with their journal number.'
                            : '${waiting.length == 1 ? '1 payment is' : '${waiting.length} payments are'} waiting. '
                                'Check each journal number with the bank.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (settings != null &&
                        settings.account == null &&
                        access.can(VenuePermission.edit))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          child: ListTile(
                            leading: const Icon(Icons.account_balance_rounded),
                            title: const Text('Set up your bank account'),
                            subtitle: const Text(
                                'Members can pay online once it\'s set up: its QR code shows when they pay.'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () =>
                                context.go(GymRoutes.settingsFor(venueId)),
                          ),
                        ),
                      ),
                    if (waiting.isEmpty)
                      const EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'Nothing to confirm',
                        message:
                            'When a member pays online and gives the journal number, it waits here.',
                      )
                    else ...[
                      SectionTitle('Waiting (${waiting.length})'),
                      _ClaimsTable(
                          claims: waiting,
                          venueId: venueId,
                          canConfirm: access.can(GymPermission.payments)),
                    ],
                    if (answered.isNotEmpty) ...[
                      const SectionTitle('Answered'),
                      _ClaimsTable(
                          claims: answered,
                          venueId: venueId,
                          canConfirm: access.can(GymPermission.payments)),
                    ],
                  ],
                ),
              );
            },
          ),
          ),
        );
      },
    );
  }
}

/// On a member's page: their online payment waiting, to confirm there.
class MemberPaymentsWaiting extends ConsumerWidget {
  final String gymMemberId;
  final bool canConfirm;

  const MemberPaymentsWaiting(
      {super.key, required this.gymMemberId, required this.canConfirm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting =
        (ref.watch(gymMemberClaimsProvider(gymMemberId)).valueOrNull ??
                const <PaymentClaim>[])
            .where((c) => c.isPending)
            .toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Payment to confirm'),
        for (final c in waiting)
          PaymentClaimCard(claim: c, canConfirm: canConfirm, showMember: false),
      ],
    );
  }
}

// ─── The gym's settings ────────────────────────────────────────────────────

/// Membership settings: the gym's bank account (its QR code shows when a
/// member pays online, and at the front desk), when members are reminded
/// that their package ends, and who answers requests to join. For those who
/// edit the gym.
class MembershipSettingsScreen extends ConsumerWidget {
  final String venueId;

  const MembershipSettingsScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Membership settings',
      permission: VenuePermission.edit,
      builder: (context, access) => AsyncValueView<GymSettings>(
        value: ref.watch(gymSettingsProvider(venueId)),
        onRetry: () => ref.invalidate(gymSettingsProvider(venueId)),
        data: (settings) => _SettingsForm(access: access, settings: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final VenueAccess access;
  final GymSettings settings;

  const _SettingsForm({required this.access, required this.settings});

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late String? _bank = widget.settings.account?.bankName;
  late final _number =
      TextEditingController(text: widget.settings.account?.accountNumber ?? '');
  late final _holder = TextEditingController(
      text: widget.settings.account?.accountName ?? widget.access.venue.name);
  late final Set<int> _days = {...widget.settings.reminderDays};
  late String _joins = widget.settings.joinApproval;
  late final String? _paymentQrPath = widget.settings.paymentQrPath;
  ({Uint8List bytes, String contentType})? _pickedQr;
  bool _removeQr = false;
  bool _saving = false;

  String get _venueId => widget.access.venue.id;

  String get _digits => _number.text.replaceAll(RegExp(r'[\s-]'), '');
  String get repoPaymentQrUrl =>
      ref
          .read(gymRepositoryProvider)
          .paymentQrUrl(_paymentQrPath ?? widget.settings.paymentQrPath) ??
      '';

  /// The account as typed, when it's whole; null while there's none.
  PaymentAccount? get _account => _bank != null &&
          RegExp(r'^[0-9]{6,20}$').hasMatch(_digits) &&
          _holder.text.trim().length >= 2
      ? PaymentAccount(
          bankName: _bank!,
          accountNumber: _digits,
          accountName: _holder.text.trim())
      : null;

  /// Nothing typed: the gym takes payments at the desk only.
  bool get _noAccount => _bank == null && _digits.isEmpty;

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(gymRepositoryProvider);
    final ok = await runAction(
      context,
      () async {
        final oldPath = widget.settings.paymentQrPath;
        var path = _removeQr ? null : _paymentQrPath;
        if (_pickedQr != null) {
          path = await repo.uploadPaymentQr(
              _venueId, _pickedQr!.bytes, _pickedQr!.contentType);
        }
        await repo.saveSettings(GymSettings(
          venueId: _venueId,
          account: _noAccount ? null : _account,
          paymentQrPath: _noAccount ? null : path,
          reminderDays: (_days.toList()..sort((a, b) => b.compareTo(a))),
          joinApproval: _joins,
        ));
        if (oldPath != null && oldPath != path) {
          await repo.removePaymentQr(oldPath);
        }
      },
      success: 'Saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ref.invalidate(gymSettingsProvider(_venueId));
      ref.invalidate(myMembershipsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final options = {...reminderDayOptions, ..._days}.toList()..sort();
    final account = _account;

    Widget choice(String value, String title, String subtitle) {
      final on = _joins == value;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
            on
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: on ? brand.accent : brand.muted),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: () => setState(() => _joins = value),
      );
    }

    return AppPage(
      title: 'Membership settings',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save settings'),
            ),
          ],
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: pagePadding(context),
          children: [
            ResponsiveColumns(
              first: [
                const SectionTitle('Paying online'),
                SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'The bank account members pay into. When a member pays (in the app, or at the front desk), Health Pro '
                        'shows its QR code with the amount; they pay in their bank app and give the journal number (JRN), '
                        'and you confirm it under Payments to confirm. Until it\'s set up, members pay at the desk only.',
                        style: TextStyle(color: brand.body, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      SearchableDropdown<String>(
                        value: _bank,
                        decoration: const InputDecoration(
                            labelText: 'Bank',
                            prefixIcon: Icon(Icons.account_balance_rounded)),
                        options: [
                          for (final b in {
                            ...bhutanBanks,
                            if (_bank != null) _bank!
                          })
                            DropdownOption(b, b),
                        ],
                        onChanged: (b) => setState(() => _bank = b),
                        validator: (b) =>
                            b == null && !_noAccount ? 'Choose the bank' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _number,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]'))
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Account number',
                            prefixIcon: Icon(Icons.pin_outlined)),
                        onChanged: (_) => setState(() {}),
                        validator: (_) => _noAccount ||
                                RegExp(r'^[0-9]{6,20}$').hasMatch(_digits)
                            ? null
                            : 'Enter the account number: 6 to 20 digits',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _holder,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Account name',
                          helperText:
                              'As the bank has it: payers check it before they pay.',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) =>
                            _noAccount || (v ?? '').trim().length >= 2
                                ? null
                                : 'Enter the account name',
                      ),
                      if (!_noAccount) ...[
                        const SizedBox(height: 14),
                        Text('Bank-issued payment QR',
                            style: TextStyle(
                                color: brand.body,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          'Upload the QR image provided by your bank and confirm it belongs to this account. The amount is shown separately.',
                            style: TextStyle(color: brand.muted, height: 1.35)),
                        const SizedBox(height: 10),
                        if (_pickedQr != null)
                          Image.memory(_pickedQr!.bytes,
                              width: 180, height: 180, fit: BoxFit.contain)
                        else if (!_removeQr && _paymentQrPath != null)
                          Image.network(repoPaymentQrUrl,
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 100,
                                  child: Center(
                                      child:
                                          Icon(Icons.broken_image_outlined)))),
                        Wrap(spacing: 8, children: [
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final photo = await pickPhoto(context, imageQuality: 100);
                                    if (photo != null) {
                                      setState(() {
                                        _pickedQr = photo;
                                        _removeQr = false;
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.upload_outlined),
                            label: Text(_paymentQrPath == null || _removeQr
                                ? 'Upload QR code'
                                : 'Change QR code'),
                          ),
                          if (_paymentQrPath != null || _pickedQr != null)
                            TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                          _pickedQr = null;
                                          _removeQr = true;
                                        }),
                                child: const Text('Remove QR')),
                        ]),
                        FormField<bool>(
                          validator: (_) => (_pickedQr != null ||
                                  (!_removeQr && _paymentQrPath != null))
                              ? null
                              : 'Upload the QR image issued by your bank',
                          builder: (field) => field.errorText == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(field.errorText!,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                                ),
                        ),
                      ],
                      if (!_noAccount)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() {
                              _bank = null;
                              _number.clear();
                            }),
                            child: const Text(
                                'Remove: take payments at the desk only'),
                          ),
                        ),
                    if (account != null &&
                        !_removeQr &&
                        _pickedQr == null &&
                        repoPaymentQrUrl.isNotEmpty) ...[
                        const Divider(height: 28),
                        Text('What payers see',
                            style: TextStyle(
                                color: brand.muted,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Center(
                            child: PaymentQrCard(
                                account: account,
                                qrImageUrl: ref
                                        .read(gymRepositoryProvider)
                                        .paymentQrUrl(_paymentQrPath ??
                                            widget.settings.paymentQrPath) ??
                                    '',
                                size: 150)),
                      ],
                      const Divider(height: 28),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        enabled: false,
                        leading: const Icon(Icons.bolt_rounded),
                        title: const Text('Online payment gateway (RMA)'),
                        subtitle: const Text(
                            'Coming later: members pay from their own account and it\'s confirmed by itself, without the journal number.'),
                        trailing:
                            StatusChip(label: 'Not yet', color: brand.muted),
                      ),
                    ],
                  ),
                ),
              ],
              second: [
                const SectionTitle('Reminders'),
                SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Remind members this many days before their package ends (members with the app):',
                          style: TextStyle(color: brand.body, height: 1.4)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in options)
                            FilterChip(
                              label: Text(d == 1 ? '1 day' : '$d days'),
                              selected: _days.contains(d),
                              onSelected: (on) => setState(
                                  () => on ? _days.add(d) : _days.remove(d)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _days.isEmpty
                            ? 'No reminders before. On the last day they\'re still told it ends, and how to renew.'
                            : 'On the last day they\'re also told it ends, and how to renew.',
                        style: TextStyle(color: brand.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Requests to join'),
                SectionCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    children: [
                      choice(JoinApproval.desk, 'The front desk',
                          'Whoever registers members adds or declines them.'),
                      choice(
                          JoinApproval.managers,
                          'The owner and managers only',
                          'The front desk sees requests but can\'t answer them.'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── The member: paying online ─────────────────────────────────────────────

/// A member pays their gym online: they choose the package and go on to
/// pay; the gym's payment QR code (made from its bank account, with the
/// amount) appears; they pay in their bank app and give the journal number. The
/// gym confirms it and the package starts (from the day the current one
/// ends, or today); they're told either way.
class PayOnlineScreen extends ConsumerWidget {
  final String venueId;

  const PayOnlineScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Pay online',
      body: AsyncValueView<MyMemberships>(
        value: ref.watch(myMembershipsProvider),
        onRetry: () => ref.invalidate(myMembershipsProvider),
        data: (mine) {
          final gym = mine.at(venueId);
          if (gym == null || gym.gymMemberId == null) {
            return EmptyState(
              icon: Icons.fitness_center_rounded,
              title: "You're not a member of this gym yet",
              message: 'Ask to join first; then you can pay here.',
              actionLabel: 'Open the gym',
              onAction: () => context.go(GymRoutes.gymFor(venueId)),
            );
          }
          if (gym.claim?.status == ClaimStatus.pending) {
            return EmptyState(
              icon: Icons.hourglass_top_rounded,
              title: 'Your payment is waiting',
              message:
                  '${gym.venueName} is checking JRN ${gym.claim!.jrn}. You\'ll be told when it\'s confirmed.',
              actionLabel: 'Back to My gym',
              onAction: () => context.go(GymRoutes.my),
            );
          }
          if (!gym.canPayOnline) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: '${gym.venueName} takes payments at the front desk',
              message:
                  'Pay there, in cash or as they ask; they renew your package.',
            );
          }
          return _PayForm(gym: gym);
        },
      ),
    );
  }
}

class _PayForm extends ConsumerStatefulWidget {
  final MyGym gym;

  const _PayForm({required this.gym});

  @override
  ConsumerState<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends ConsumerState<_PayForm> {
  final _form = GlobalKey<FormState>();
  final _jrn = TextEditingController();
  final _amount = TextEditingController();
  GymPlan? _plan;
  int _months = 1;
  bool _amountTouched = false;
  bool _sending = false;

  /// They chose the package and went on to pay: the QR code shows.
  bool _paying = false;

  @override
  void dispose() {
    _jrn.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _choose(GymPlan plan, {int? months}) {
    setState(() {
      _plan = plan;
      _months = months ?? defaultMonths(plan);
      if (!_amountTouched) _amount.text = '${packagePrice(plan, _months)}';
    });
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate() || _plan == null) return;
    setState(() => _sending = true);
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).claimPayment(
            widget.gym.venueId,
            planId: _plan!.id,
            months: _months,
            amount: int.parse(_amount.text.trim()),
            jrn: _jrn.text,
          ),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) return;
    ref.invalidate(myMembershipsProvider);
    showFeedback(context,
        'Sent. ${widget.gym.venueName} will confirm it, and you\'ll be told.');
    context.go(GymRoutes.my);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final gym = widget.gym;
    final plans =
        ref.watch(gymPlansProvider((venueId: gym.venueId, all: false)));
    final list = plans.valueOrNull ?? const <GymPlan>[];
    if (_plan == null && list.isNotEmpty) {
      final usual =
          list.where((p) => p.name == gym.planName).firstOrNull ?? list.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _plan == null) _choose(usual);
      });
    }
    final amount = int.tryParse(_amount.text.trim());
    Widget step(int n, String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: brand.accent.withValues(alpha: 0.14),
                child: Text('$n',
                    style: TextStyle(
                        color: brand.accent, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    child,
                  ],
                ),
              ),
            ],
          ),
        );

    return Form(
      key: _form,
      child: ListView(
        padding: pagePadding(context),
        children: [
          Text(gym.venueName,
              style: context.text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Your new package starts the day your current one ends (or today, if it has), once the gym confirms your payment.',
            style: TextStyle(color: brand.muted),
          ),
          const SizedBox(height: 20),
          ResponsiveColumns(
            spacing: 32,
            first: [
              step(
                1,
                'Choose your package',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchableDropdown<String>(
                      value: _plan?.id,
                      decoration: const InputDecoration(labelText: 'Package *'),
                      options: [
                        for (final p in list)
                          DropdownOption(p.id,
                              '${p.name} · ${p.price == 0 ? 'Free' : formatNu(p.price)} / ${formatDuration(p.durationDays)}'),
                      ],
                      onChanged: (id) {
                        final p = list.where((p) => p.id == id).firstOrNull;
                        if (p != null) _choose(p);
                      },
                      validator: (id) =>
                          id == null ? 'Choose the package' : null,
                    ),
                    const SizedBox(height: 12),
                    SearchableDropdown<int>(
                      key: ValueKey('months-${_plan?.id}'),
                      value: _months,
                      decoration: const InputDecoration(labelText: 'For *'),
                      options: [
                        for (final m in packageMonthOptions)
                          DropdownOption(m, m == 1 ? '1 month' : '$m months')
                      ],
                      onChanged: _plan == null
                          ? null
                          : (m) => _choose(_plan!, months: m),
                    ),
                  ],
                ),
              ),
              if (!_paying)
                Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 18),
                  child: FilledButton.icon(
                    onPressed: _plan == null
                        ? null
                        : () => setState(() => _paying = true),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: Text(amount == null || amount < 1
                        ? 'Proceed to pay'
                        : 'Proceed to pay ${formatNu(amount)}'),
                  ),
                )
              else
                step(
                  2,
                  'Pay${amount == null || amount < 1 ? '' : ' ${formatNu(amount)}'} in your bank app',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: PaymentQrCard(
                          account: gym.paymentAccount!,
                          qrImageUrl: gym.paymentQrUrl!,
                          amount: amount,
                          note: [gym.venueName, if (_plan != null) _plan!.name]
                              .join(', '),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Scan the code, or send the amount to this account from your bank app. Check the account name '
                        'before you pay.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: brand.muted, fontSize: 12.5),
                      ),
                      if (gym.paymentInfo != null) ...[
                        const SizedBox(height: 12),
                        InfoRow(
                            icon: Icons.info_outline_rounded,
                            text: gym.paymentInfo!),
                      ],
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Amount you paid (Nu.) *',
                            prefixText: 'Nu. '),
                        onChanged: (_) => setState(() => _amountTouched = true),
                        validator: (v) =>
                            (int.tryParse((v ?? '').trim()) ?? 0) < 1
                                ? 'Enter the amount you paid'
                                : null,
                      ),
                    ],
                  ),
                ),
            ],
            second: !_paying
                ? const []
                : [
                    step(
                      3,
                      'Enter the journal number',
                      TextFormField(
                        controller: _jrn,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Journal number (JRN) *',
                          helperText:
                              "It's on your bank app's receipt, after you pay.",
                          prefixIcon: Icon(Icons.receipt_long_rounded),
                        ),
                        validator: (v) => RegExp(r'^[0-9A-Za-z/-]{4,40}$')
                                .hasMatch(
                                    (v ?? '').replaceAll(RegExp(r'\s'), ''))
                            ? null
                            : 'Enter the journal number from the receipt',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text("I've paid: send it to the gym"),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The gym checks the journal number with the bank, then confirms it. Until then you can\'t check in on a '
                      'package that has ended.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: brand.muted, fontSize: 12.5),
                    ),
                  ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
