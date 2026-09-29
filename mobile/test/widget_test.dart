import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Ludo World Free App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LudoWorldFreeApp(),
      ),
    );

    expect(find.byType(LudoWorldFreeApp), findsOneWidget);
  });
}
