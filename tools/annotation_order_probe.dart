import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/annotations/domain/annotation_order.dart';

void main() {
  void before(Map a, Map b) {
    if (compareAnnotationLocations({'anchor': a}, {'anchor': b}) >= 0) {
      throw StateError('Annotations are out of reading order');
    }
  }

  before({'page': 0}, {'page': 1});
  before(
    {
      'page': 1,
      'segments': [
        {'start': 50},
      ],
    },
    {
      'page': 1,
      'segments': [
        {'start': 200},
      ],
    },
  );
  before(
    {
      'page': 1,
      'point': [0, 700],
    },
    {
      'page': 1,
      'point': [0, 500],
    },
  );
  before(
    {'cfi': 'epubcfi(/6/2[chapter999]!/4/2/1:3)'},
    {'cfi': 'epubcfi(/6/4[chapter1]!/4/2/1:1)'},
  );
  before(
    {'cfi': 'epubcfi(/6/2!/4/2,/1:3,/1:8)'},
    {'cfi': 'epubcfi(/6/2!/4/2/1:10)'},
  );
  stdout.writeln(
    jsonEncode({
      'status': 'passed',
      'checks': 5,
      'scope': 'Annotation ordering, independent of creation time',
    }),
  );
}
