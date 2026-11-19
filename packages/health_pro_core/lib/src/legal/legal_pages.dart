import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/launch.dart';
import '../widgets/app_page.dart';
import '../widgets/art3d.dart';
import '../widgets/feedback.dart';
import '../widgets/motion.dart';
import '../widgets/view_tabs.dart';

/// Who runs Health Pro, for the privacy policy and the terms. Keep the pages
/// true to what the app does: a change in what's collected or who it's
/// shared with changes [LegalDoc.privacy] and [updated] too.
abstract final class LegalInfo {
  static const company = 'Innovates';

  /// Where people write about their data and these terms. Set it before the
  /// pages go live: until then they say an address is coming.
  static const contactEmail = '';

  /// When the pages last changed.
  static const updated = '18 November 2026';
}

/// One part of a legal page: its [icon], [heading] and paragraphs; one
/// starting '• ' is a bullet.
class LegalSection {
  final IconData icon;
  final String heading;
  final List<String> paragraphs;

  const LegalSection(this.icon, this.heading, this.paragraphs);
}

/// The terms and the privacy policy: each one's name, its page (for links
/// from outside, such as the app stores), the few lines that matter most, and
/// the full text.
enum LegalDoc {
  terms('Terms of use', CoreRoutes.terms, Icons.description_outlined, Art3D.memo),
  privacy('Privacy policy', CoreRoutes.privacy, Icons.shield_outlined, Art3D.key);

  final String title;
  final String route;
  final IconData icon;
  final Art3D art;

  const LegalDoc(this.title, this.route, this.icon, this.art);

  List<String> get intro => this == terms ? _termsIntro : _privacyIntro;
  List<String> get summary => this == terms ? _termsSummary : _privacySummary;
  List<LegalSection> get sections => this == terms ? _termsSections : _privacySections;
}

const _c = LegalInfo.company;

const _privacyIntro = [
  'Health Pro connects gyms in Bhutan with their members and trainers. It is run by $_c. This page explains what '
      'Health Pro keeps about you, why, who can see it, and what you can do about it.',
  'Each gym decides what it records about its own members; $_c runs the system for the gym and the Health Pro team '
      'looks after it.',
];

const _privacySummary = [
  'We don\'t sell your information or use it for advertising.',
  'A gym sees only its own members, and its staff see what their role allows.',
  'Everything travels encrypted, and your sign-in code is stored scrambled.',
  'You can correct your details, or delete your account, at any time.',
];

const _privacySections = [
  LegalSection(Icons.inventory_2_outlined, 'What we keep', [
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
  LegalSection(Icons.lightbulb_outline_rounded, 'Why we use it', [
    '• To run your membership: check-ins with your QR code, renewals, payments and reminders.',
    '• So your gym knows who you are and can keep you safe: your emergency contact, blood group and medical issues '
        'are there for the gym to help you if something happens.',
    '• To send you codes to sign in, and notifications about your membership, payments and trainers.',
    '• To show gyms and trainers to people looking for one, with their reviews.',
    '• To keep Health Pro safe and working, and to fix errors.',
  ]),
  LegalSection(Icons.visibility_outlined, 'Who can see it', [
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
  LegalSection(Icons.schedule_rounded, 'How long we keep it', [
    'While you have an account, or are a member of a gym. When you delete your account (Account, then Delete '
        'account), your profile, memberships, check-ins, staff places, reviews and notifications are deleted. '
        'Payments stay in the gyms\' records, without your name, because gyms need them for their accounts.',
    'A gym keeps the member record it made for you at the desk until it removes it: ask the gym. Copies kept as '
        'backups are replaced over time.',
  ]),
  LegalSection(Icons.tune_rounded, 'Your choices', [
    '• See and correct your details in Account, then Edit profile; ask your gym to correct its record of you.',
    '• Turn notifications off on the Notifications page, or in your browser or phone.',
    '• Delete your account at any time in Account.',
    '• Write to us for a copy of what we keep about you, or to have something corrected or removed. We answer '
        'within 30 days.',
  ]),
  LegalSection(Icons.family_restroom_rounded, 'Children', [
    'If you are under 18, a parent or guardian should agree to you joining a gym and giving your details.',
  ]),
  LegalSection(Icons.lock_outline_rounded, 'Keeping it safe', [
    'Everything travels encrypted (HTTPS). The database itself decides who may see what, so each person, gym and '
        'trainer sees only what they are allowed to. No system is perfect: if something looks wrong, tell us.',
  ]),
  LegalSection(Icons.update_rounded, 'Changes', [
    'When this page changes, the date above changes too. We tell you in the app about bigger changes.',
  ]),
];

const _termsIntro = [
  'Health Pro connects gyms in Bhutan with their members and trainers. It is run by $_c. By creating an account or '
      'using Health Pro, you agree to these terms and to the privacy policy.',
];

const _termsSummary = [
  'Give true details, and keep your sign-in code and QR code to yourself.',
  'Your membership, its prices and refunds are between you and your gym.',
  'You pay the gym directly: Health Pro never holds your money.',
  'Health Pro and Ask AI give general information, not medical advice.',
];

const _termsSections = [
  LegalSection(Icons.person_outline_rounded, 'Your account', [
    '• Give true details, and keep your 6-digit sign-in code to yourself.',
    '• One account is for one person. You are responsible for what is done with yours; tell us if someone else '
        'used it.',
  ]),
  LegalSection(Icons.fitness_center_rounded, 'Your gym and your membership', [
    'Your membership is between you and your gym. The gym sets its packages, prices, opening hours, rules, and its '
        'cancellation and refund policy. $_c doesn\'t run the gyms and isn\'t part of that agreement.',
    'Your Health Pro QR code is yours alone: don\'t share it. A gym may turn you away when your membership has run '
        'out, or when the person showing the code isn\'t you.',
  ]),
  LegalSection(Icons.payments_outlined, 'Payments', [
    'You pay the gym directly: at the desk, or by bank transfer to the gym\'s account with the journal number (JRN). '
        'Health Pro doesn\'t take or hold your money. A renewal starts once the gym confirms your payment. For a '
        'refund, ask the gym.',
  ]),
  LegalSection(Icons.favorite_border_rounded, 'Your health', [
    'Talk to a doctor before you start exercising if you have a health condition, tell your gym about any medical '
        'issues, and follow your gym\'s and trainer\'s instructions. What Health Pro and Ask AI tell you is general '
        'information, not medical advice.',
  ]),
  LegalSection(Icons.storefront_outlined, 'Gyms, staff and trainers', [
    '• Keep your details true: the gym\'s profile and prices, and trainers\' certificates.',
    '• Use members\' details only to run their memberships, keep them confidential, and follow the law.',
    '• $_c may check a gym or trainer, and hide or remove one that is false or misused.',
  ]),
  LegalSection(Icons.rate_review_outlined, 'Reviews and what you add', [
    'Reviews must be honest and about your own experience: no abuse, hate, other people\'s personal details or '
        'advertising. We may remove anything that breaks these rules. Photos and text you add stay yours; you let us '
        'show them in Health Pro.',
  ]),
  LegalSection(Icons.block_rounded, 'Don\'t misuse Health Pro', [
    'Don\'t try to get into other people\'s accounts or information, break or overload the system, copy its contents '
        'in bulk, or set up false gyms or profiles.',
  ]),
  LegalSection(Icons.report_problem_outlined, 'When things go wrong', [
    'We work to keep Health Pro running, but it may sometimes be unavailable or have mistakes, and its features may '
        'change. Health Pro is provided as it is. As far as the law allows, $_c isn\'t responsible for a gym\'s '
        'services, for injuries at a gym, or for losses because Health Pro wasn\'t available. Nothing here takes away '
        'rights you have by law.',
  ]),
  LegalSection(Icons.logout_rounded, 'Ending', [
    'You can delete your account at any time in Account. We may suspend or close an account that breaks these terms.',
  ]),
  LegalSection(Icons.balance_rounded, 'The law', [
    'These terms are governed by the laws of the Kingdom of Bhutan.',
  ]),
  LegalSection(Icons.update_rounded, 'Changes', [
    'When these terms change, the date above changes too, and we tell you in the app about bigger changes. Using '
        'Health Pro after a change means you accept it.',
  ]),
];

/// The terms or the privacy policy over the page they were opened from, so
/// no one leaves what they were doing: a sheet on a phone, a dialog on wider
/// screens. Both switch between the two in place.
Future<void> showLegal(BuildContext context, LegalDoc doc) {
  final size = MediaQuery.sizeOf(context);
  if (size.width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.92, child: _LegalModal(doc: doc, sheet: true)),
    );
  }
  return showAppDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 760, height: math.min(860.0, size.height * 0.88), child: _LegalModal(doc: doc, sheet: false)),
    ),
  );
}

/// /privacy: what Health Pro collects, why, who sees it, how long it's kept,
/// and people's choices. Open to everyone (the app stores link to it).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const _LegalPage(doc: LegalDoc.privacy);
}

/// /terms: the rules for using Health Pro. Open to everyone.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _LegalPage(doc: LegalDoc.terms);
}

/// '[lead] Terms of use and Privacy policy', centred: the foot of the sign-up
/// form. Each opens over the page ([showLegal]); the account page has its
/// own row for them.
class LegalLinks extends StatelessWidget {
  /// Before the links, e.g. 'By registering, you agree to the'.
  final String lead;

  const LegalLinks({super.key, required this.lead});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = TextButton.styleFrom(
      foregroundColor: brand.accentText,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w600, fontSize: 13.5),
    );
    final muted = TextStyle(color: brand.muted, fontSize: 13.5, fontFamily: brandFont);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(lead, style: muted),
        TextButton(style: style, onPressed: () => showLegal(context, LegalDoc.terms), child: const Text('Terms of use')),
        Text('and', style: muted),
        TextButton(style: style, onPressed: () => showLegal(context, LegalDoc.privacy), child: const Text('Privacy policy')),
      ],
    );
  }
}

/// The two, side by side, to switch between them.
const _tabs = [
  ViewTab(value: LegalDoc.terms, label: 'Terms of use', icon: Icons.description_outlined),
  ViewTab(value: LegalDoc.privacy, label: 'Privacy policy', icon: Icons.shield_outlined),
];

/// [showLegal]'s content: the page's 3D art, name and date with a close
/// button, the switch, the text scrolling under them, and Done at the foot.
class _LegalModal extends StatefulWidget {
  final LegalDoc doc;
  final bool sheet;

  const _LegalModal({required this.doc, required this.sheet});

  @override
  State<_LegalModal> createState() => _LegalModalState();
}

class _LegalModalState extends State<_LegalModal> {
  late LegalDoc _doc = widget.doc;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final pad = widget.sheet ? 18.0 : 24.0;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, widget.sheet ? 0 : 20, 10, 14),
          child: Row(
            children: [
              _ArtTile(doc: _doc, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: brand.ink, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                    const SizedBox(height: 3),
                    Text('Last updated ${LegalInfo.updated}', style: TextStyle(color: brand.muted, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: brand.muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 14),
          child: ViewTabs<LegalDoc>(tabs: _tabs, selected: _doc, onChanged: (d) => setState(() => _doc = d)),
        ),
        Divider(height: 1, color: brand.fieldBorder.withValues(alpha: 0.5)),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.hover),
            switchInCurve: Motion.ease,
            switchOutCurve: Motion.easeIn,
            child: SelectionArea(
              key: ValueKey(_doc),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 20, pad, 24),
                child: _LegalBody(doc: _doc),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: brand.fieldBorder.withValues(alpha: 0.5)),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 12 + (widget.sheet ? bottom : 0)),
          child: Row(
            children: [
              if (!widget.sheet)
                Expanded(
                  child: Text('Using Health Pro means you agree to both.', style: TextStyle(color: brand.muted, fontSize: 13)),
                ),
              if (widget.sheet)
                Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')))
              else
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
            ],
          ),
        ),
      ],
    );
  }
}

/// /privacy and /terms opened straight from a link: the same text as
/// [showLegal], as a page in a readable column.
class _LegalPage extends StatelessWidget {
  final LegalDoc doc;

  const _LegalPage({required this.doc});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return AppPage(
      title: doc.title,
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
            Row(
              children: [
                _ArtTile(doc: doc, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.title, style: TextStyle(color: brand.ink, fontSize: 26, fontWeight: FontWeight.w900, height: 1.2)),
                      const SizedBox(height: 4),
                      Text('Last updated ${LegalInfo.updated}', style: TextStyle(color: brand.muted, fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ViewTabs<LegalDoc>(tabs: _tabs, selected: doc, onChanged: (d) => context.pushReplacement(d.route)),
            const SizedBox(height: 22),
            _LegalBody(doc: doc),
          ],
        ),
      ),
    );
  }
}

/// The page's 3D art on a soft tile in the highlight colour.
class _ArtTile extends StatelessWidget {
  final LegalDoc doc;
  final double size;

  const _ArtTile({required this.doc, required this.size});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.highlight.withValues(alpha: brand.isLight ? 0.12 : 0.18),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Art3DIcon(doc.art, size: size * 0.6, fallback: doc.icon, fallbackColor: brand.highlight),
    );
  }
}

/// A page's text: the opening, the short version on a tinted card, each
/// section under its icon, and how to reach us.
class _LegalBody extends StatelessWidget {
  final LegalDoc doc;

  const _LegalBody({required this.doc});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = TextStyle(color: brand.body, fontSize: 15, height: 1.6);
    Widget paragraph(String p) {
      if (!p.startsWith('• ')) return Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p, style: text));
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 10),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: brand.highlight, shape: BoxShape.circle)),
            ),
            Expanded(child: Text(p.substring(2), style: text)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in doc.intro) paragraph(p),
        const SizedBox(height: 8),
        _Summary(points: doc.summary),
        const SizedBox(height: 12),
        for (final s in doc.sections)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _IconTile(icon: s.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s.heading, style: TextStyle(color: brand.ink, fontSize: 17, fontWeight: FontWeight.w800, height: 1.25)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final p in s.paragraphs) paragraph(p),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const _Contact(),
      ],
    );
  }
}

/// A section's icon on a small soft tile.
class _IconTile extends StatelessWidget {
  final IconData icon;

  const _IconTile({required this.icon});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: brand.accent.withValues(alpha: brand.isLight ? 0.1 : 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: brand.accentText),
    );
  }
}

/// 'In short': the lines that matter most, ticked, before the full text.
class _Summary extends StatelessWidget {
  final List<String> points;

  const _Summary({required this.points});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: brand.highlight.withValues(alpha: brand.isLight ? 0.07 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.highlight.withValues(alpha: brand.isLight ? 0.22 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: brand.highlight),
              const SizedBox(width: 8),
              Text('In short', style: TextStyle(color: brand.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, size: 18, color: brand.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p, style: TextStyle(color: brand.ink, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w500))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 'Contact us': the address to write to, or that it's coming.
class _Contact extends StatelessWidget {
  const _Contact();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final text = TextStyle(color: brand.body, fontSize: 14.5, height: 1.5);
    const email = LegalInfo.contactEmail;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: brand.surfaceAlt, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _IconTile(icon: Icons.mail_outline_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contact us', style: TextStyle(color: brand.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                if (email.isEmpty)
                  Text('Our contact address for ${LegalInfo.company} is coming soon. Until then, ask at your gym\'s front '
                      'desk, and they will pass it on.', style: text)
                else
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Questions about your data or these terms? Write to ${LegalInfo.company} at ', style: text),
                      InkWell(
                        onTap: () => openExternal(context, Uri(scheme: 'mailto', path: email)),
                        child: Text(email,
                            style: text.copyWith(color: brand.accentText, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                      ),
                      Text('.', style: text),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
