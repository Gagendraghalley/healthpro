import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:gym_membership/src/widgets/delete_member_dialog.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// Records what it was asked to delete.
class _DeleteRepo extends Fake implements GymRepository {
  final calls = <(String, bool)>[];

  @override
  Future<bool> deleteMember(String gymMemberId, {bool evenIfActive = false}) async {
    calls.add((gymMemberId, evenIfActive));
    return true;
  }
}

final _member = GymMember.fromJson({
  'id': 'm1',
  'venue_id': 'g1',
  'code': 'K7P9QA',
  'qr_token': '0123456789abcdef0123456789abcdef',
  'full_name': 'Karma Wangmo',
  'phone': '+97517123456',
  'joined_on': '2026-11-01',
  'created_at': '2026-11-01T03:00:00Z',
});

Future<bool?> _open(WidgetTester tester, _DeleteRepo repo, {DateTime? activeUntil}) async {
  bool? result;
  await tester.pumpWidget(ProviderScope(
    overrides: [gymRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result =
                await showDeleteMemberDialog(context, member: _member, gymName: 'Peak Fitness', activeUntil: activeUntil),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

/// The dialog's filled button labelled [label] (FilledButton.icon is a subtype).
Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton));

void main() {
  testWidgets('still paid for: it warns, and Delete waits for the tick', (tester) async {
    final repo = _DeleteRepo();
    final t = BhutanTime.today();
    final until = DateTime(t.year, t.month, t.day + 9);
    await _open(tester, repo, activeUntil: until);

    expect(find.textContaining('still active until ${formatDate(until)} (10 days left)'), findsOneWidget);
    expect(find.textContaining('Their Health Pro account stays'), findsOneWidget);
    final delete = _button('Delete anyway');
    expect(tester.widget<FilledButton>(delete).onPressed, isNull, reason: 'not before they tick');

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.text('I understand their paid membership ends now'));
    await tester.pump();
    expect(tester.widget<FilledButton>(delete).onPressed, isNotNull);
    await tester.tap(delete);
    await tester.pumpAndSettle();

    expect(repo.calls, [('m1', true)]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Deleted Karma Wangmo. They were told in Health Pro.'), findsOneWidget);
  });

  testWidgets('no package: no warning, deleted at once', (tester) async {
    final repo = _DeleteRepo();
    await _open(tester, repo);

    expect(find.textContaining('still active'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(_button('Delete member'));
    await tester.pumpAndSettle();
    expect(repo.calls, [('m1', false)]);
  });

  testWidgets('Cancel deletes nothing', (tester) async {
    final repo = _DeleteRepo();
    await _open(tester, repo);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
  });
}
