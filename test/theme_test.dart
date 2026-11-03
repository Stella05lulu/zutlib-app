import 'package:flutter_test/flutter_test.dart';
import 'package:zutlib/core/theme.dart';
import 'package:zutlib/core/theme/app_theme.dart';
import 'package:zutlib/models/resource.dart';
import 'package:zutlib/ui/widgets/common.dart';

void main() {
  group('One look for the whole app', () {
    test('the older palette names are the study colours', () {
      for (final (old, now) in [
        (AppColors.light, StudyColors.light),
        (AppColors.dark, StudyColors.dark),
      ]) {
        expect(old.ink, now.ink);
        expect(old.accent, now.accent);
        expect(old.canvas, now.canvas);
        expect(old.surface, now.surface);
        expect(old.line, now.line);
        expect(old.bad, now.danger);
        expect(old.good, now.success);
        expect(old.warn, now.warn);
      }
    });

    test('corners match the study radii', () {
      expect(Corners.card, Radii.panel);
      expect(Corners.field, Radii.control);
      expect(Corners.chip, Radii.tag);
    });

    test('every resource type has its own solid cover colour', () {
      final fills = {for (final t in ResourceType.values) KitPalette.fill(resourceTypeColorKey(t))};
      expect(fills.length, ResourceType.values.length);
    });
  });
}
