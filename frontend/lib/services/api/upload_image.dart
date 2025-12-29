import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:imgrep/services/api/user.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/utils/settings.dart';

Future<Map<String, dynamic>?> uploadImage(
  String imagePath,
  String userId,
  String serverIp,
  DateTime createdAt,
  double? latitude,
  double? longitude,
) async {
  try {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$serverIp/api/upload-image'),
    );
    request.fields['user_id'] = userId;

    request.fields['created_at'] = createdAt.toIso8601String();
    request.fields['latitude'] = (latitude == null) ? '' : latitude.toString();
    request.fields['longitude'] =
        (longitude == null) ? '' : longitude.toString();

    request.files.add(await http.MultipartFile.fromPath('image', imagePath));
    request.headers['Content-Type'] = 'multipart/form-data';

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    Map<String, dynamic> data = jsonDecode(responseBody);
    return data;
  } catch (e) {
    Dbg.crash('Error: $e');
    return null;
  }
}

Future<Map<String, dynamic>?> imageToImageSearch(String imagePath, String userId) async {
  try {
    final apiUrl = Settings.serverIp;
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiUrl/api/search/image'),
    );
    request.fields['user_id'] = userId;
    request.files.add(await http.MultipartFile.fromPath('image', imagePath));
    request.headers['Content-Type'] = 'multipart/form-data';

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    Map<String, dynamic> data = jsonDecode(responseBody);
    return data;
  } catch (e) {
    Dbg.crash('Error: $e');
    return null;
  }
}

Future<Map<String, dynamic>?> searchImage(String query, int amount) async {
  try {
    final userId = await UserManager.getUserId();

    if (userId == null) {
      Dbg.crash("userid is not defined");
      return null;
    }
    final apiUrl = Settings.serverIp;
    final response = await http.post(
      Uri.parse('$apiUrl/api/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'query': query, 'amount': amount}),
    );

    Map<String, dynamic> data = jsonDecode(response.body);
    return data;
  } catch (e) {
    Dbg.e('Error: $e');
    return null;
  }
}

Future<String> getCaption(String imageId) async {
  try {
    final faissId = await DatabaseService.getFiassIdfromId(imageId);
    final userId = await UserManager.getUserId();

    if (faissId == null) {
      Dbg.crash("faissId is null");
      throw Exception("faissId is not defined");
    }

    final apiUrl = Settings.serverIp;
    final response = await http.post(
      Uri.parse('$apiUrl/api/get-caption'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'faiss_id': faissId.toString(), 'user_id': userId}),
    );


    final Map<String, dynamic> data = jsonDecode(response.body);

    if (!data.containsKey('caption')) {
      throw Exception("Response missing 'caption' key");
    }

    final dynamic caption = data['caption'];

    if (caption == null || caption is! String) {
      Dbg.e("Caption is invalid: $caption");
      throw Exception("Caption is null or not a String");
    }

    return caption;
  } catch (e, stack) {
    Dbg.e('Exception: $e\n$stack');
    throw Exception('Failed to get caption: $e');
  }
}

