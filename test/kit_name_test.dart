import 'package:flutter_test/flutter_test.dart';

import 'package:zutlib/study/kit_name.dart';

void main() {
  group('Kit names from files', () {
    test('one file: its tidy name', () {
      expect(kitNameFromFiles(['BIT4440_CloudComputing_7. Stream Processing.pdf']),
          'BIT4440 Cloud Computing 7. Stream Processing');
    });

    test('several lectures of one course: what they share', () {
      expect(
        kitNameFromFiles([
          'BIT4440_CloudComputing_7. Stream Processing.pdf',
          'BIT4440_CloudComputing_6. Big Data Analytics.pdf',
          'BIT4440_CloudComputing_1. Introduction.pdf',
        ]),
        'BIT4440 Cloud Computing',
      );
    });

    test('numbering words at the end are dropped', () {
      expect(kitNameFromFiles(['Networks Lecture 1.pdf', 'Networks Lecture 2.pdf']), 'Networks');
    });

    test('unrelated files: the first name and how many more', () {
      expect(kitNameFromFiles(['Ethics.pdf', 'Databases.pdf', 'Maths.pdf']), 'Ethics and 2 more');
    });

    test('nothing to go on: the fallback', () {
      expect(kitNameFromFiles(const []), 'My study kit');
    });
  });
}
