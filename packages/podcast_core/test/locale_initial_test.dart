import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_core/services/locale_service.dart';

void main() {
  test('novi korisnik dobiva zadani jezik brenda', () {
    expect(resolveInitialLocale(null, 'en'), const Locale('en'));
    expect(resolveInitialLocale(null, 'hr'), const Locale('hr'));
  });

  test('spremljeni izbor ima prednost pred brendom', () {
    expect(resolveInitialLocale('hr', 'en'), const Locale('hr'));
    expect(resolveInitialLocale('en', 'hr'), const Locale('en'));
  });

  test('nepoznata vrijednost pada na hrvatski', () {
    expect(resolveInitialLocale('de', 'en'), const Locale('hr'));
  });
}
