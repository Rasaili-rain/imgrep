import 'package:flutter_dotenv/flutter_dotenv.dart';

class Settings {
  static const int initialPageSize = 30;
  // Amount of images that gets loaded at the startup
  static const int pageSize = 100;
  // Amount of images that gets loaded in background during scrolling
  static const int batchSize = 100;
  // Amount of images that stored once in database
  static String serverIp = dotenv.env['SERVER_IP'] ?? "http://192.168.254.243:5000"
}
