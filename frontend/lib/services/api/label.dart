import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/utils/settings.dart';


Future<String?> getLabelById(String? labelId) async {
  if (labelId == null) return null;
  if (labelId == "null") return null; // Dont know why do i have to do this

  try {
    final apiUrl = Settings.serverIp;
    final response = await http.get(
      Uri.parse('$apiUrl/api/label/get/$labelId'),
    );
    Map<String, dynamic> data = jsonDecode(response.body);
    return data["name"];
  } catch (e) {
    Dbg.crash('Error: $e');
    return null;
  }
}

Future<Map<String, dynamic>?> updateLabel(String labelId, String name) async {
  try {
    final apiUrl = Settings.serverIp;
    final response = await http.post(
      Uri.parse('$apiUrl/api/label/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "label_id": labelId,
        "name": name,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      Dbg.crash('Error: ${response.body}');
      return null;
    }
  } catch (e) {
    Dbg.crash('Error: $e');
    return null;
  }
}
