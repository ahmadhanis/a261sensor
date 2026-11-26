import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttapp/main.dart';

// Generate local visual QA images without committing platform-specific goldens:
// flutter test --update-goldens tool/render_preview_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontFile = [
      'C:/Windows/Fonts/segoeui.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
    ].map(File.new).firstWhere((file) => file.existsSync());
    final bytes = await fontFile.readAsBytes();
    final textFont = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    final codeFont = FontLoader('monospace')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([textFont.load(), codeFont.load(), iconFont.load()]);
  });
  for (final preview in {
    'desktop': const Size(1280, 1280),
    'mobile': const Size(390, 2100),
  }.entries) {
    testWidgets('${preview.key} dashboard preview', (tester) async {
      tester.view.physicalSize = preview.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MainApp),
        matchesGoldenFile('../build/previews/${preview.key}.png'),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
