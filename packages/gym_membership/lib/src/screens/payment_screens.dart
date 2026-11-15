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

// ─── The desk: confirming online payments ─────────────────────────────────

/// Confirms [claim] after the desk has found it in the bank's records: the
/// package starts, and the member is told.
Future<void> confirmPaymentClaim(BuildContext context, WidgetRef ref, PaymentClaim claim) async {
  final sure = await confirmAction(
    context,
    title: "Confirm ${claim.memberName}'s payment?",
    message: 'First find journal number ${claim.jrn} for ${formatNu(claim.amount)} in the bank\'s records. '
        'Confirming starts ${claim.planName} for ${claim.monthsLabel}, and tells them.',
    confirmLabel: 'Confirm payment',
  );
  if (!sure || !context.mounted) return;
  DateTime? end;
  final ok = await runAction(context, () async => end = await ref.read(gymRepositoryProvider).confirmClaim(claim.id));
  if (!ok || !context.mounted) return;
  refreshGym(ref, claim.venueId);
  ref.invalidate(gymMemberProvider(claim.gymMemberId));
  showFeedback(context, 'Confirmed: ${claim.planName} until ${formatDate(end!)}');
}

/// Says the payment couldn't be found, with why for the member.
Future<void> rejectPaymentClaim(BuildContext context, WidgetRef ref, PaymentClaim claim) async {
  final note = await askText(
    context,
    title: "Couldn't find it?",
    hint: 'For ${claim.memberName} (optional): e.g. not in our statement, check the number',
    confirmLabel: 'Tell them',
  );
  if (note == null || !context.mounted) return;
  final ok = await runAction(context, () => ref.read(gymRepositoryProvider).rejectClaim(claim.id, note: note),
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

  const PaymentClaimCard({super.key, required this.claim, required this.canConfirm, this.showMember = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final plans = ref.watch(gymPlansProvider((venueId: claim.venueId, all: true))).valueOrNull ?? const <GymPlan>[];
    final plan = plans.where((p) => p.id == claim.planId).firstOrNull;
    final price = plan == null ? null : packagePrice(plan, claim.months);
    final differs = price != null && price != claim.amount;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
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
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text('Sent ${timeAgo(claim.createdAt)}', style: TextStyle(color: brand.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Text(formatNu(claim.amount), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          InfoRow(icon: Icons.sell_outlined, text: '${claim.planName} · ${claim.monthsLabel}'),
          if (differs)
            InfoRow(icon: Icons.info_outline_rounded, text: 'The price for that is ${formatNu(price)}.'),
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: brand.muted),
              const SizedBox(width: 10),
              Text('JRN ', style: TextStyle(color: brand.muted)),
              Flexible(
                child: SelectableText(claim.jrn,
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontFeatures: [FontFeature.tabularFigures()])),
              ),
              IconButton(
                tooltip: 'Copy the journal number',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: claim.jrn));
                  if (context.mounted) showFeedback(context, 'Copied ${claim.jrn}');
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
                OutlinedButton(onPressed: () => rejectPaymentClaim(context, ref, claim), child: const Text('Not found')),
              ],
            ),
          ] else if (claim.isPending)
            Text('Someone who takes payments confirms it.', style: TextStyle(color: brand.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Payments to confirm: members who paid online with the gym's payment QR
/// and gave the journal number. The desk checks each with the bank, then
/// confirms it (their package starts) or says it couldn't find it.
class PaymentsToConfirmScreen extends ConsumerWidget {
  final String venueId;

  const PaymentsToConfirmScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Payments to confirm',
      permission: GymPermission.payments,
      builder: (context, access) {
        final claims = ref.watch(gymPaymentClaimsProvider(venueId));
        final settings = ref.watch(gymSettingsProvider(venueId)).valueOrNull;
        return AppPage(
          title: 'Payments to confirm',
          body: AsyncValueView<List<PaymentClaim>>(
            value: claims,
            onRetry: () => ref.invalidate(gymPaymentClaimsProvider(venueId)),
            data: (list) {
              final waiting = list.where((c) => c.isPending).toList();
              final answered = list.where((c) => !c.isPending).take(30).toList();
              return RefreshIndicator(
                onRefresh: () => ref.refresh(gymPaymentClaimsProvider(venueId).future),
                child: ListView(
                  padding: pagePadding(context),
                  children: [
                    if (settings != null && settings.paymentQrPath == null && access.can(VenuePermission.edit))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          child: ListTile(
                            leading: const Icon(Icons.qr_code_2_rounded),
                            title: const Text('Add your payment QR code'),
                            subtitle: const Text('Members scan it in their bank app to pay online.'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.go(GymRoutes.settingsFor(venueId)),
                          ),
                        ),
                      ),
                    if (waiting.isEmpty)
                      const EmptyState(
                        icon: Icons.verified_outlined,
                        title: 'Nothing to confirm',
                        message: 'When a member pays online and gives the journal number, it waits here.',
                      )
                    else ...[
                      SectionTitle('Waiting (${waiting.length})'),
                      ResponsiveGrid(
                        minItemWidth: 340,
                        maxColumns: 3,
                        equalHeight: false,
                        children: [
                          for (final c in waiting) PaymentClaimCard(claim: c, canConfirm: access.can(GymPermission.payments)),
                        ],
                      ),
                    ],
                    if (answered.isNotEmpty) ...[
                      const SectionTitle('Answered'),
                      SectionCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final c in answered)
                              ListTile(
                                title: Text('${c.memberName} · ${formatNu(c.amount)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  ['JRN ${c.jrn}', timeAgo(c.decidedAt ?? c.createdAt), if (c.decisionNote != null) c.decisionNote!]
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: StatusChip(
                                  label: c.status.label,
                                  color: c.status == ClaimStatus.confirmed ? context.brand.success : context.brand.danger,
                                ),
                                onTap: () => context.go(GymRoutes.memberFor(venueId, c.gymMemberId)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
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

  const MemberPaymentsWaiting({super.key, required this.gymMemberId, required this.canConfirm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = (ref.watch(gymMemberClaimsProvider(gymMemberId)).valueOrNull ?? const <PaymentClaim>[])
        .where((c) => c.isPending)
        .toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Payment to confirm'),
        for (final c in waiting) PaymentClaimCard(claim: c, canConfirm: canConfirm, showMember: false),
      ],
    );
  }
}

// ─── The gym's settings ────────────────────────────────────────────────────

/// Membership settings: the bank's payment QR code (members scan it to pay
/// online), when members are reminded that their package ends, and who
/// answers requests to join. For those who edit the gym.
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
  late String? _qrPath = widget.settings.paymentQrPath;
  late final Set<int> _days = {...widget.settings.reminderDays};
  late String _joins = widget.settings.joinApproval;
  bool _uploading = false;
  bool _saving = false;

  String get _venueId => widget.access.venue.id;

  Future<void> _upload() async {
    final photo = await pickPhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _uploading = true);
    await runAction(context, () async {
      final path = await ref.read(gymRepositoryProvider).uploadPaymentQr(_venueId, photo.bytes, photo.contentType);
      if (mounted) setState(() => _qrPath = path);
    });
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref.read(gymRepositoryProvider).saveSettings(GymSettings(
            venueId: _venueId,
            paymentQrPath: _qrPath,
            reminderDays: (_days.toList()..sort((a, b) => b.compareTo(a))),
            joinApproval: _joins,
          )),
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
    final info = widget.access.venue.paymentInfo;
    final options = {...reminderDayOptions, ..._days}.toList()..sort();

    Widget choice(String value, String title, String subtitle) {
      final on = _joins == value;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            color: on ? brand.accent : brand.muted),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onTap: () => setState(() => _joins = value),
      );
    }

    return AppPage(
      title: 'Membership settings',
      maxWidth: AppPage.readableWidth,
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: _saving || _uploading ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Save settings'),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          const SectionTitle('Paying online'),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your bank\'s payment QR code. Members scan it in their bank app, pay, and enter the journal '
                  'number (JRN) in Health Pro; you confirm it under Payments to confirm.',
                  style: TextStyle(color: brand.body, height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: brand.fieldBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _uploading
                          ? const Center(child: HealthProLoader(size: 32, semanticsLabel: 'Uploading'))
                          : _qrPath == null
                              ? Icon(Icons.qr_code_2_rounded, size: 64, color: brand.muted.withValues(alpha: 0.5))
                              : Image.network(ref.read(gymRepositoryProvider).paymentQrUrl(_qrPath!), fit: BoxFit.contain,
                                  semanticLabel: 'Your payment QR code',
                                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: brand.muted)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _uploading ? null : _upload,
                          icon: const Icon(Icons.upload_rounded),
                          label: Text(_qrPath == null ? 'Upload payment QR' : 'Replace it'),
                        ),
                        if (_qrPath != null)
                          TextButton(
                            onPressed: () => setState(() => _qrPath = null),
                            child: const Text('Remove: take payments at the desk only'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  text: info == null ? 'No payment details yet (e.g. the account name and bank).' : 'Shown with it: $info',
                ),
                if (widget.access.can(VenuePermission.edit))
                  TextButton(
                    onPressed: () => context.go(CoreRoutes.editVenueFor(_venueId)),
                    child: const Text('Change the payment details in Gym settings'),
                  ),
              ],
            ),
          ),
          const SectionTitle('Reminders'),
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remind members this many days before their package ends (members with the app):',
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
                        onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                choice(JoinApproval.desk, 'The front desk', 'Whoever registers members adds or declines them.'),
                choice(JoinApproval.managers, 'The owner and managers only', 'The front desk sees requests but can\'t answer them.'),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── The member: paying online ─────────────────────────────────────────────

/// A member pays their gym online: they choose the package, scan the gym's
/// payment QR code in their bank app, pay, and give the journal number. The
/// gym confirms it and the package starts (from the day the current one
/// ends, or today); they're told either way.
class PayOnlineScreen extends ConsumerWidget {
  final String venueId;

  const PayOnlineScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Pay online',
      maxWidth: AppPage.readableWidth,
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
              message: '${gym.venueName} is checking JRN ${gym.claim!.jrn}. You\'ll be told when it\'s confirmed.',
              actionLabel: 'Back to My gyms',
              onAction: () => context.go(GymRoutes.my),
            );
          }
          if (!gym.canPayOnline) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: '${gym.venueName} takes payments at the front desk',
              message: 'Pay there, in cash or as they ask; they renew your package.',
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
    showFeedback(context, 'Sent. ${widget.gym.venueName} will confirm it, and you\'ll be told.');
    context.go(GymRoutes.my);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final gym = widget.gym;
    final plans = ref.watch(gymPlansProvider((venueId: gym.venueId, all: false)));
    final list = plans.valueOrNull ?? const <GymPlan>[];
    if (_plan == null && list.isNotEmpty) {
      final usual = list.where((p) => p.name == gym.planName).firstOrNull ?? list.first;
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
                child: Text('$n', style: TextStyle(color: brand.accent, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
          Text(gym.venueName, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Your new package starts the day your current one ends (or today, if it has), once the gym confirms your payment.',
            style: TextStyle(color: brand.muted),
          ),
          const SizedBox(height: 20),
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
                      DropdownOption(
                          p.id, '${p.name} · ${p.price == 0 ? 'Free' : formatNu(p.price)} / ${formatDuration(p.durationDays)}'),
                  ],
                  onChanged: (id) {
                    final p = list.where((p) => p.id == id).firstOrNull;
                    if (p != null) _choose(p);
                  },
                  validator: (id) => id == null ? 'Choose the package' : null,
                ),
                const SizedBox(height: 12),
                SearchableDropdown<int>(
                  key: ValueKey('months-${_plan?.id}'),
                  value: _months,
                  decoration: const InputDecoration(labelText: 'For *'),
                  options: [for (final m in packageMonthOptions) DropdownOption(m, m == 1 ? '1 month' : '$m months')],
                  onChanged: _plan == null ? null : (m) => _choose(_plan!, months: m),
                ),
              ],
            ),
          ),
          step(
            2,
            'Scan this in your bank app and pay${amount == null ? '' : ' ${formatNu(amount)}'}',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gym.paymentQrPath != null)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: brand.cardShadow,
                      ),
                      child: Image.network(
                        ref.read(gymRepositoryProvider).paymentQrUrl(gym.paymentQrPath!),
                        fit: BoxFit.contain,
                        semanticLabel: '${gym.venueName}\'s payment QR code',
                        errorBuilder: (_, __, ___) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text("The QR code didn't load. Use the details below."),
                        ),
                      ),
                    ),
                  ),
                if (gym.paymentInfo != null) ...[
                  const SizedBox(height: 12),
                  InfoRow(icon: Icons.account_balance_wallet_outlined, text: gym.paymentInfo!),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Amount you paid (Nu.) *', prefixText: 'Nu. '),
                  onChanged: (_) => setState(() => _amountTouched = true),
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Enter the amount you paid' : null,
                ),
              ],
            ),
          ),
          step(
            3,
            'Enter the journal number',
            TextFormField(
              controller: _jrn,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Journal number (JRN) *',
                helperText: "It's on your bank app's receipt, after you pay.",
                prefixIcon: Icon(Icons.receipt_long_rounded),
              ),
              validator: (v) => RegExp(r'^[0-9A-Za-z/-]{4,40}$').hasMatch((v ?? '').replaceAll(RegExp(r'\s'), ''))
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
