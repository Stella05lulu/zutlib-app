/// A study kit's name from the files it is made from, when the student
/// leaves the name empty. With several files it is what their names have
/// in common ("BIT4440_CloudComputing_6. Big Data.pdf" and
/// "BIT4440_CloudComputing_7. Streams.pdf" give "BIT4440 Cloud Computing"),
/// not just the first file's name. Plain Dart, tested in
/// test/kit_name_test.dart.
library;

/// "BIT4440_CloudComputing_7. Stream Processing.pdf" becomes
/// "BIT4440 Cloud Computing 7. Stream Processing".
String tidyFileName(String name) {
  var s = name.trim();
  if (s.toLowerCase().endsWith('.pdf')) s = s.substring(0, s.length - 4);
  s = s.replaceAll(RegExp(r'[_]+'), ' ');
  s = s.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// Words that only number a part ("Lecture 3", "Week 2", "7.", "-").
final _numbering = RegExp(r'^(\d+[.)]?|[-:.]+|lecture|lec|week|wk|chapter|ch|unit|part|topic|module|notes?)$',
    caseSensitive: false);

String kitNameFromFiles(List<String> fileNames, {String fallback = 'My study kit'}) {
  final names = [for (final n in fileNames) tidyFileName(n)].where((n) => n.isNotEmpty).toList();
  if (names.isEmpty) return fallback;
  if (names.length == 1) return names.first;
  final words = [for (final n in names) n.split(' ')];
  final common = <String>[];
  for (var i = 0; i < words.first.length; i++) {
    final w = words.first[i];
    if (words.every((ws) => i < ws.length && ws[i].toLowerCase() == w.toLowerCase())) {
      common.add(w);
    } else {
      break;
    }
  }
  while (common.isNotEmpty && _numbering.hasMatch(common.last)) {
    common.removeLast();
  }
  final joined = common.join(' ').trim();
  if (RegExp(r'[A-Za-z]{2,}').hasMatch(joined) && joined.length >= 4) return joined;
  final more = names.length - 1;
  return '${names.first} and $more more';
}
