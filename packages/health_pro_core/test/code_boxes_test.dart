import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/auth/auth_layout.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester,
      {bool hidden = false, bool showPaste = false, ValueChanged<String>? onCompleted}) async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Form(
          key: form,
          child: Column(
            children: [
              CodeBoxes(
                controller: controller,
                hidden: hidden,
                showPaste: showPaste,
                validator: Validators.signInCode,
                onCompleted: onCompleted,
              ),
              TextButton(onPressed: () => form.currentState!.validate(), child: const Text('Go')),
            ],
          ),
        ),
      ),
    ));
    return controller;
  }

  testWidgets('six boxes take a digit each, and no more than six', (tester) async {
    String? done;
    final controller = await pump(tester, onCompleted: (v) => done = v);
    expect(find.byType(AnimatedContainer), findsNWidgets(6));

    await tester.tap(find.byType(CodeBoxes));
    await tester.enterText(find.byType(TextField), '04');
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(done, isNull);

    await tester.enterText(find.byType(TextField), '0412967');
    await tester.pump();
    expect(controller.text, '041296');
    expect(done, '041296');
  });

  testWidgets('hidden shows dots, and a short code is refused', (tester) async {
    await pump(tester, hidden: true);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('1'), findsNothing);

    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(find.text('Enter your 6-digit code'), findsOneWidget);
  });

  test('finds the code in what was copied', () {
    expect(CodeBoxes.codeIn('895955', 6), '895955');
    expect(CodeBoxes.codeIn('8 9 5 9 5 5', 6), '895955');
    expect(CodeBoxes.codeIn('895-955', 6), '895955');
    expect(CodeBoxes.codeIn('895955 is your Health Pro code. It works for 1 hour.', 6), '895955');
    expect(CodeBoxes.codeIn('no digits', 6), '');
  });

  testWidgets('a pasted code takes the place of what was typed', (tester) async {
    String? done;
    final controller = await pump(tester, onCompleted: (v) => done = v);
    await tester.tap(find.byType(CodeBoxes));
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();

    // Pasted after the typed digits, with a space in it.
    const pasted = '12895 955';
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: pasted, selection: TextSelection.collapsed(offset: pasted.length)));
    await tester.pump();
    expect(controller.text, '895955');
    expect(done, '895955');

    // All six filled, then another code pasted: the new one wins.
    const again = '895955Your code is 401273';
    tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: again, selection: TextSelection.collapsed(offset: again.length)));
    await tester.pump();
    expect(controller.text, '401273');
    expect(done, '401273');
  });

  testWidgets('Paste code fills the boxes from the clipboard', (tester) async {
    var copied = '8 9 5 9 5 5';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return call.method == 'Clipboard.getData' ? <String, dynamic>{'text': copied} : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    String? done;
    final controller = await pump(tester, showPaste: true, onCompleted: (v) => done = v);

    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(controller.text, '895955');
    expect(done, '895955');

    copied = 'nothing here';
    await tester.tap(find.text('Paste code'));
    await tester.pump();
    expect(controller.text, '895955');
    expect(find.textContaining('No code copied yet'), findsOneWidget);
  });
}
