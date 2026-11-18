import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/launch.dart';
import '../widgets/app_page.dart';

/// Who runs Health Pro, for the privacy policy and the terms. Keep the pages
/// true to what the app does: a change in what's collected or who it's
/// shared with changes [PrivacyPolicyScreen] and [updated] too.
abstract final class LegalInfo {
  static const company = 'Innovates';

  /// Where people write about their data and these terms. Set it before the
  /// pages go live: until then they say an address is coming.
  static const contactEmail = '';

  /// When the pages last changed.
  static const updated = '18 November 2026';
}

/// /privacy: what Health Pro collects, why, who sees it, how long it's kept,
/// and people's choices. Open to everyone (the app stores link to it).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _c = LegalInfo.company;

  static const sections = [
    _Section(null, [
      'Health Pro connects gyms in Bhutan with their members and trainers. It is run by $_c. This page explains what '
          'Health Pro keeps about you, why, who can see it, and what you can do about it.',
      'Each gym decides what it records about its own members; $_c runs the system for the gym and the Health Pro '
          'team looks after it. We don\'t sell your information or use it for advertising.',
    ]),
    _Section('What we keep', [
      '• Your account: your name, email, phone number (if you give it), profile photo, and preferences such as '
          'colours and light or dark. Your 6-digit sign-in code is stored scrambled, so no one can read it.',
      '• When a gym registers you as a member: your name, phone, email, dzongkhag and village, occupation, '
          'emergency contact, blood group, date of birth, the date you joined, your package, any medical issues you '
          'tell the gym, and a photo taken at the desk.',
      '• What you do at gyms: memberships and renewals, check-ins (date and time), payments (amount, how you paid, and '
          'the bank journal number (JRN) for online payments), requests to join, your trainer, and reviews you write.',
      '• Trainers: your profile, certificates, timings, the gyms you work at, and your attendance at each.',
      '• Gyms: business details, contact details, location, photos, video links, prices, and the bank details and '
          'payment QR code members pay with.',
      '• Notifications: if you allow them, an address your browser or phone gives us to deliver them.',
      '• Errors: when the app goes wrong, what went wrong, the page, the kind of device, and your account if you are '
          'signed in, so we can fix it. Kept 90 days.',
      '• Near me: your location is used on your device to sort gyms by distance. We don\'t store it.',
      '• Ask AI: your question is sent to Cloudflare\'s AI service to be answered. We keep only when you asked (for '
          'the daily limit), not the question.',
    ]),
    _Section('Why we use it', [
      '• To run your membership: check-ins with your QR code, renewals, payments and reminders.',
      '• So your gym knows who you are and can keep you safe: your emergency contact, blood group and medical issues '
          'are there for the gym to help you if something happens.',
      '• To send you codes to sign in, and notifications about your membership, payments and trainers.',
      '• To show gyms and trainers to people looking for one, with their reviews.',
      '• To keep Health Pro safe and working, and to fix errors.',
    ]),
    _Section('Who can see it', [
      '• The gyms you are a member of: their staff, by their role (front desk, managers, owner). A gym sees only its '
          'own members.',
      '• Your trainer sees what they need to train you.',
      '• The Health Pro team at $_c, to support you and run the service.',
      '• Everyone: gym profiles, trainers\' public profiles, and reviews (with the reviewer\'s name). Profile photos, '
          'gym photos, and trainers\' photos and certificates are public pictures: anyone with their link can see '
          'them. Members\' photos taken at the desk are not public.',
      '• Companies that run parts of Health Pro for us, only for that: Supabase (our database, sign-in and file '
          'storage, on servers in Singapore), Cloudflare (the website and Ask AI), Google (sends our emails), '
          'OpenStreetMap (the maps) and your browser\'s or phone\'s push service (delivers notifications).',
      '• Anyone the law of Bhutan requires us to tell.',
    ]),
    _Section('How long we keep it', [
      'While you have an account, or are a member of a gym. When you delete your account (Account, then Delete '
          'account), your profile, memberships, check-ins, staff places, reviews and notifications are deleted. '
          'Payments stay in the gyms\' records, without your name, because gyms need them for their accounts.',
      'A gym keeps the member record it made for you at the desk until it removes it: ask the gym. Copies kept as '
          'backups are replaced over time.',
    ]),
    _Section('Your choices', [
      '• See and correct your details in Account, then Edit profile; ask your gym to correct its record of you.',
      '• Turn notifications off on the Notifications page, or in your browser or phone.',
      '• Delete your account at any time in Account.',
      '• Write to us for a copy of what we keep about you, or to have something corrected or removed. We answer '
          'within 30 days.',
    ]),
    _Section('Children', [
      'If you are under 18, a parent or guardian should agree to you joining a gym and giving your details.',
    ]),
    _Section('Keeping it safe', [
      'Everything travels encrypted (HTTPS). The database itself decides who may see what, so each person, gym and '
          'trainer sees only what they are allowed to. No system is perfect: if something looks wrong, tell us.',
    ]),
    _Section('Changes', [
      'When this page changes, the date above changes too. We tell you in the app about bigger changes.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return const _LegalPage(
      title: 'Privacy policy',
      sections: sections,
      other: ('Terms of use', CoreRoutes.terms),
    );
  }
}

/// /terms: the rules for using Health Pro. Open to everyone.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _c = LegalInfo.company;

  static const sections = [
    _Section(null, [
      'Health Pro connects gyms in Bhutan with their members and trainers. It is run by $_c. By creating an account '
          'or using Health Pro, you agree to these terms and to the privacy policy.',
    ]),
    _Section('Your account', [
      '• Give true details, and keep your 6-digit sign-in code to yourself.',
      '• One account is for one person. You are responsible for what is done with yours; tell us if someone else '
          'used it.',
    ]),
    _Section('Your gym and your membership', [
      'Your membership is between you and your gym. The gym sets its packages, prices, opening hours, rules, and its '
          'cancellation and refund policy. $_c doesn\'t run the gyms and isn\'t part of that agreement.',
      'Your Health Pro QR code is yours alone: don\'t share it. A gym may turn you away when your membership has run '
          'out, or when the person showing the code isn\'t you.',
    ]),
    _Section('Payments', [
      'You pay the gym directly: at the desk, or by bank transfer to the gym\'s account with the journal number (JRN). '
          'Health Pro doesn\'t take or hold your money. A renewal starts once the gym confirms your payment. For a '
          'refund, ask the gym.',
    ]),
    _Section('Your health', [
      'Talk to a doctor before you start exercising if you have a health condition, tell your gym about any medical '
          'issues, and follow your gym\'s and trainer\'s instructions. What Health Pro and Ask AI tell you is general '
          'information, not medical advice.',
    ]),
    _Section('Gyms, staff and trainers', [
      '• Keep your details true: the gym\'s profile and prices, and trainers\' certificates.',
      '• Use members\' details only to run their memberships, keep them confidential, and follow the law.',
      '• $_c may check a gym or trainer, and hide or remove one that is false or misused.',
    ]),
    _Section('Reviews and what you add', [
      'Reviews must be honest and about your own experience: no abuse, hate, other people\'s personal details or '
          'advertising. We may remove anything that breaks these rules. Photos and text you add stay yours; you let us '
          'show them in Health Pro.',
    ]),
    _Section('Don\'t misuse Health Pro', [
      'Don\'t try to get into other people\'s accounts or information, break or overload the system, copy its '
          'contents in bulk, or set up false gyms or profiles.',
    ]),
    _Section('When things go wrong', [
      'We work to keep Health Pro running, but it may sometimes be unavailable or have mistakes, and its features may '
          'change. Health Pro is provided as it is. As far as the law allows, $_c isn\'t responsible for a gym\'s '
          'services, for injuries at a gym, or for losses because Health Pro wasn\'t available. Nothing here takes '
          'away rights you have by law.',
    ]),
    _Section('Ending', [
      'You can delete your account at any time in Account. We may suspend or close an account that breaks these '
          'terms.',
    ]),
    _Section('The law', [
      'These terms are governed by the laws of the Kingdom of Bhutan.',
    ]),
    _Section('Changes', [
      'When these terms change, the date above changes too, and we tell you in the app about bigger changes. Using '
          'Health Pro after a change means you accept it.',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return const _LegalPage(
      title: 'Terms of use',
      sections: sections,
      other: ('Privacy policy', CoreRoutes.privacy),
    );
  }
}

/// 'Privacy policy · Terms of use', small and centred: the foot of the
/// account page and the sign-up form.
class LegalLinks extends StatelessWidget {
  /// Before the links, e.g. 'By registering, you agree to the'.
  final String? lead;

  const LegalLinks({super.key, this.lead});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = TextButton.styleFrom(
      foregroundColor: brand.accent,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
    );
    final muted = TextStyle(color: brand.muted, fontSize: 13.5);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (lead != null) Text(lead!, style: muted),
        TextButton(style: style, onPressed: () => context.push(CoreRoutes.terms), child: const Text('Terms of use')),
        Text(lead == null ? '·' : 'and', style: muted),
        TextButton(style: style, onPressed: () => context.push(CoreRoutes.privacy), child: const Text('Privacy policy')),
      ],
    );
  }
}

/// A heading (none for the opening) and its paragraphs; one starting '• ' is
/// a bullet.
class _Section {
  final String? heading;
  final List<String> paragraphs;

  const _Section(this.heading, this.paragraphs);
}

/// A page of text in a readable column: the title, when it last changed, the
/// sections, how to reach us, and the other page.
class _LegalPage extends StatelessWidget {
  final String title;
  final List<_Section> sections;
  final (String, String) other;

  const _LegalPage({required this.title, required this.sections, required this.other});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = TextStyle(color: brand.body, fontSize: 15, height: 1.55);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    Widget paragraph(String p) {
      if (!p.startsWith('• ')) return Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(p, style: text));
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: text.copyWith(color: brand.accent, fontWeight: FontWeight.w800)),
            Expanded(child: Text(p.substring(2), style: text)),
          ],
        ),
      );
    }

    Widget heading(String h) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(h, style: TextStyle(color: brand.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        );

    const email = LegalInfo.contactEmail;
    return AppPage(
      title: title,
      maxWidth: AppPage.readableWidth,
      leading: IconButton(
        tooltip: canPop ? 'Back' : 'Health Pro',
        icon: Icon(canPop ? Icons.arrow_back_rounded : Icons.home_outlined),
        onPressed: () => canPop ? context.pop() : context.go(CoreRoutes.root),
      ),
      body: SelectionArea(
        child: ListView(
          padding: pagePadding(context, top: 20, bottom: 40),
          children: [
            Text(title, style: TextStyle(color: brand.ink, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
            const SizedBox(height: 6),
            Text('Last updated ${LegalInfo.updated}', style: TextStyle(color: brand.muted, fontSize: 13.5)),
            const SizedBox(height: 20),
            for (final s in sections) ...[
              if (s.heading != null) heading(s.heading!),
              for (final p in s.paragraphs) paragraph(p),
            ],
            heading('Contact us'),
            if (email.isEmpty)
              Text('Our contact address for ${LegalInfo.company} is coming soon. Until then, ask at your gym\'s front '
                  'desk, and they will pass it on.', style: text)
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Write to ${LegalInfo.company} at ', style: text),
                  InkWell(
                    onTap: () => openExternal(context, Uri(scheme: 'mailto', path: email)),
                    child: Text(email,
                        style: text.copyWith(color: brand.accent, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                  ),
                  Text('.', style: text),
                ],
              ),
            const SizedBox(height: 28),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => context.pushReplacement(other.$2),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(other.$1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
