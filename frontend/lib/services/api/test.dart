import 'package:http/http.dart' as http;
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/utils/settings.dart';

//just a api test ignore

Future<bool> isApiRunningCorrectly() async {
  try {
    final apiUrl = Settings.serverIp;
    final response = await http.get(
      Uri.parse('$apiUrl/test'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      Dbg.i('Success: ${response.body}');
      return true;
    } else {
      Dbg.e('Error: Status ${response.statusCode}, Body: ${response.body}');
    }
  } catch (e) {
    Dbg.e('Error: $e');
  }
  return false;
}
