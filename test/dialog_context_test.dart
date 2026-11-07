import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A dialog that ignores its own context and closes with the screen's one
/// pops the wrong navigator. On a tab page that removes the page itself and
/// leaves a blank app, which is what Cancel request once did.
void main() {
  test('dialogs close with their own context', () {
    final dialog = RegExp(r'show(Dialog|ModalBottomSheet)(<[^>]*>)?\(');
    final problems = <String>[];

    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in dialog.allMatches(source)) {
        // The whole showDialog(...) call, by balancing brackets.
        var depth = 0;
        var end = match.end - 1;
        for (; end < source.length; end++) {
          if (source[end] == '(') depth++;
          if (source[end] == ')' && --depth == 0) break;
        }
        final call = source.substring(match.start, end);
        final ignoresOwnContext = RegExp(r'builder:\s*\(_\)').hasMatch(call);
        if (ignoresOwnContext && call.contains('Navigator.pop(context')) {
          final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
          problems.add('${file.path}:$line');
        }
      }
    }

    expect(problems, isEmpty);
  });
}
