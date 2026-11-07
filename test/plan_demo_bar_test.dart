import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zutlib/core/theme/app_theme.dart';
import 'package:zutlib/state/plan_providers.dart';
import 'package:zutlib/state/providers.dart';
import 'package:zutlib/study/plan_demo.dart';
import 'package:zutlib/study/planner.dart';
import 'package:zutlib/ui/screens/plan/plan_widgets.dart';

const kit = KitProgress(sections: ['One', 'Two', 'Three'], cardIds: ['a', 'b'], questionIds: ['q']);

Future<ProviderContainer> pump(WidgetTester tester, PlanDemo demo) async {
  final container = ProviderContainer(overrides: [userIdProvider.overrideWith((ref) => null)]);
  addTearDown(container.dispose);
  container.read(planDemoProvider.notifier).state = demo;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: StudyScope(
        child: Scaffold(
          bottomNavigationBar: Consumer(builder: (context, ref, _) {
            final d = ref.watch(planDemoProvider);
            return d == null ? const SizedBox.shrink() : PlanDemoBar(demo: d);
          }),
        ),
      ),
    ),
  ));
  return container;
}

void main() {
  final settings = PlanSettings(examDate: DateTime(2026, 11, 12), startDate: DateTime(2026, 11, 2));

  testWidgets('the bar moves a day, misses a day, goes back and exits', (tester) async {
    final c = await pump(tester, PlanDemo.begin('p', settings, kit));
    expect(find.textContaining('Day 1 of 10'), findsOneWidget);

    await tester.tap(find.text('Complete day'));
    await tester.pump();
    expect(find.textContaining('Day 2 of 10'), findsOneWidget);

    await tester.tap(find.text('Miss this day'));
    await tester.pump();
    expect(find.textContaining('Day 3 of 10'), findsOneWidget);
    expect(c.read(planDemoProvider)!.health.status, PlanStatus.behind);

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.textContaining('Day 2 of 10'), findsOneWidget);

    await tester.tap(find.text('Exit demo'));
    await tester.pump();
    expect(c.read(planDemoProvider), isNull);
  });

  testWidgets('the jump button names the next phase, then the exam', (tester) async {
    await pump(tester, PlanDemo.begin('p', settings, kit));
    await tester.tap(find.text('Jump to Practise'));
    await tester.pump();
    await tester.tap(find.text('Jump to Test'));
    await tester.pump();
    await tester.tap(find.text('Jump to exam day'));
    await tester.pump();
    expect(find.textContaining('Exam day'), findsOneWidget);
    expect(find.text('Complete day'), findsNothing);
    expect(find.text('Restart'), findsOneWidget);
  });
}
