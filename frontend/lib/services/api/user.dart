import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/utils/settings.dart';

class UserManager {
  static String? _userId;

  /// Get user ID - creates one if doesn't exist
  static Future<String?> getUserId() async {
    if (_userId != null && _userId != "") return _userId;

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('user_id');
      if (_userId != null) return _userId;

      // Create new user
      final response = await http.post(
        Uri.parse('${Settings.serverIp}/api/user/new'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _userId = data['user_id']?.toString();
        if (_userId != null) {
          await prefs.setString('user_id', _userId!);
        }
        Dbg.i('Created new user eith  user ID: $_userId');
        return _userId;
      }
    } catch (e) {
      Dbg.e('Error getting user ID: $e');
    }

    return null;
  }
}
