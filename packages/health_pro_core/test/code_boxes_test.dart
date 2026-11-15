import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';
import 'package:health_pro_core/src/auth/auth_layout.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester, {bool hidden = false, ValueChanged<String>? onCompleted}) async {
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
}
