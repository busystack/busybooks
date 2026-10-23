import 'package:flutter/widgets.dart';

Locale resolveBusyBooksLocales(
  List<Locale>? requested,
  Iterable<Locale> supported,
) => basicLocaleListResolution(requested, [
  const Locale('en'),
  ...supported.where((x) => x.languageCode != 'en'),
]);
