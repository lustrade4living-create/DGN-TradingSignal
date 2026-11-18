import 'dart:convert';

import 'package:flutter/services.dart';

// Luu tru ben (JSON) + am chime intro qua MethodChannel Java tu viet
// (khong plugin Flutter). Kenh: 'tradesignal/storage' va 'tradesignal/chime'.
// Moi loi deu tra null/false, KHONG throw — de app chay tiep khi khong
// luu duoc / khong co tieng.
//
// KHONG dung AppStorage de luu API key/secret Exness hay credential nao:
// key chi giu trong bo nho phien, khong ghi ra file.
class AppStorage {
  static const _ch = MethodChannel('tradesignal/storage');

  static Future<Map<String, dynamic>?> loadJson(
      {String file = 'settings.json'}) async {
    try {
      final s = await _ch.invokeMethod<String>('load', {'file': file});
      if (s == null || s.isEmpty) return null;
      final Object? d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveJson(Map<String, dynamic> m,
      {String file = 'settings.json'}) async {
    try {
      await _ch.invokeMethod('save', {'file': file, 'json': jsonEncode(m)});
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

class ChimePlayer {
  static const _ch = MethodChannel('tradesignal/chime');

  static Future<bool> playChime() async {
    try {
      final r = await _ch.invokeMethod<bool>('playChime');
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> playTestChime() async {
    try {
      final r = await _ch.invokeMethod<bool>('playTestChime');
      return r == true;
    } catch (_) {
      return false;
    }
  }
}
