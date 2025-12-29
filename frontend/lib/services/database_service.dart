import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:imgrep/utils/debug_logger.dart';

class DatabaseService {
  static Database? _db;

  static Future<void> init() async {
    final dbPath = await getDatabasesPath();
    Dbg.i(dbPath);

    _db = await openDatabase(
      join(dbPath, "imgrep.db"),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE images(
            id TEXT PRIMARY KEY,
            path TEXT,
            created_at DATE,
            latitude REAL,
            longitude REAL,
            faiss_id INTEGER,
            label_id TEXT
          );
        ''');
        await db.execute('''
          CREATE INDEX idx_images_created_at ON images(created_at);
        ''');
        await db.execute('''
          CREATE TABLE stories (
            id TEXT PRIMARY KEY,
            title TEXT,
            description TEXT,
            image_ids TEXT,
            cover_image_id TEXT,
            created_at TEXT,
            favorite INTEGER DEFAULT 0
          );
          '''
        );
      },
    );
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  static Future<void> insertImage(AssetEntity img) async {
    final file = await img.file;
    if (file == null) return;

    // Get location data if available
    final locationData = await img.latlngAsync();

    final image = DbImage(
      id: img.id,
      path: file.path,
      createdAt: img.createDateTime,
      latitude: locationData.latitude,
      longitude: locationData.longitude,
      faissId: null,
    );

    final db = await database;
    await db.insert(
      "images",
      image.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> batchInsertImage(List<AssetEntity> imgs) async {
    final db = await database;

    final batch = db.batch();
    for (final img in imgs) {
      final file = await img.file;
      if (file == null) {
        Dbg.e("Invalid Asset File: $img");
        continue;
      }

      // Get location data if available
      final locationData = await img.latlngAsync();

      final image = DbImage(
        id: img.id,
        path: file.path,
        createdAt: img.createDateTime,
        latitude: locationData.latitude, //most likely 0
        longitude: locationData.longitude, //most likely 0
        faissId: null,
      );

      batch.insert(
        "images",
        image.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<DbImage>> getImagesPaginated(int page, int limit) async {
    final db = await database;
    final maps = await db.query(
      "images",
      orderBy: "created_at DESC",
      offset: page,
      limit: limit,
    );
    return maps.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<List<DbImage>> getUnsyncedImagesPaginated(
    int page,
    int limit,
  ) async {
    final db = await database;
    final maps = await db.query(
      "images",
      where: "faiss_id IS NULL",
      orderBy: "created_at DESC",
      offset: page,
      limit: limit,
    );
    return maps.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<void> updateFaissIndex(String id, String faissId) async {
    final db = await database;
    await db.update(
      "images",
      {"faiss_id": faissId},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  static Future<String?> getIdFromFaissIndex(String faissId) async {
    final db = await database;
    final results = await db.query(
      "images",
      columns: ["id"],
      where: "faiss_id = ?",
      whereArgs: [faissId],
    );

    if (results.isNotEmpty) {
      return results.first["id"] as String;
    }
    return null;
  }

  static Future<int?> getFiassIdfromId(String imageId) async {
    final db = await database;
    final results = await db.query(
      "images",
      columns: ["faiss_id"],
      where: "id = ?",
      whereArgs: [imageId],
    );

    if (results.isNotEmpty) {
      return results.first["faiss_id"] as int;
    }
    return null;
  }

  static Future<void> deleteImage(String id) async {
    final db = await database;
    await db.delete("images", where: "id = ?", whereArgs: [id]);
  }

  static Future<DbImage?> getImageById(String id) async {
    final db = await database;
    final maps = await db.query("images", where: "id = ?", whereArgs: [id]);

    if (maps.isNotEmpty) return DbImage.fromMap(maps.first);

    return null;
  }

  static Future<List<DbImage>> getUnsyncedImages({
    int offset = 0,
    int limit = 100,
  }) async {
    final db = await database;
    final maps = await db.query(
      "images",
      where: "faiss_id IS NULL",
      orderBy: "created_at DESC",
      offset: offset,
      limit: limit,
    );
    return maps.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<int> getUnsyncedImagesCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM images WHERE faiss_id IS NULL",
      [0],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<Map<String, int>> getSyncStats() async {
    final db = await database;

    final totalResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM images",
    );
    final total = Sqflite.firstIntValue(totalResult) ?? 0;

    final syncedResult = await db.rawQuery(
      "SELECT COUNT(*) as count FROM images WHERE faiss_id IS NOT NULL",
    );
    final synced = Sqflite.firstIntValue(syncedResult) ?? 0;

    return {'total': total, 'synced': synced, 'unsynced': total - synced};
  }

  static Future<void> markImageAsUnsynced(String id) async {
    final db = await database;
    await db.update(
      "images",
      {"faiss_id": null},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  static Future<List<DbImage>> getImagesWithDistinctLabels() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT * FROM images
      WHERE label_id IS NOT NULL AND label_id != ''
      GROUP BY label_id
      ORDER BY created_at DESC
    ''');

    return result.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<List<DbImage>> getAllImagesWithLabels() async {
    final db = await database;

    final result = await db.query(
      'images',
      where: 'label_id IS NOT NULL AND label_id != ?',
      whereArgs: [''],
      orderBy: 'created_at DESC',
    );

    return result.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<List<DbImage>> getImagesForLabel(String labelId) async {
    final db = await database;

    final result = await db.query(
      'images',
      where: 'label_id = ?',
      whereArgs: [labelId],
      orderBy: 'created_at DESC',
    );

    return result.map((map) => DbImage.fromMap(map)).toList();
  }

  static Future<int> getImageCountForLabel(String id) async {
    final db = await database;

	  final result = await db.rawQuery('''
	  	SELECT COUNT(*) as count FROM images
	  	WHERE label_id = ?
	  ''', [id]);

	  return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> updateLabelId(String id, String labelId) async {
    final db = await database;
    await db.update(
      "images",
      {"label_id": labelId},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  //STORY

  static Future<void> insertStory({
    required String id,
    required String title,
    required String description,
    required List<String> imageIds,
    required String coverImageId,
    required DateTime createdAt,
  }) async {
    final db = await database;
    await db.insert('stories', {
      'id': id,
      'title': title,
      'description': description,
      'image_ids': jsonEncode(imageIds),
      'cover_image_id': coverImageId,
      'created_at': createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
static Future<void> updateStory({
  required String title,
  required List<String> newImageIds,
  required String coverImageId
}) async {
  final db = await database;

  // 1. Get existing image IDs
  final List<Map<String, dynamic>> result = await db.query(
    'stories',
    columns: ['image_ids'],
    where: 'title = ?',
    whereArgs: [title],
  );

  if (result.isEmpty) return; 

  final existingImageIds = (jsonDecode(result[0]['image_ids']) as List<dynamic>)
      .cast<String>();

  final updatedImageIds = {...newImageIds, ...existingImageIds}.toList();

  await db.update(
    'stories',
    {'image_ids': jsonEncode(updatedImageIds)},
    where: 'title = ?',
    whereArgs: [title],
  );
    await db.update(
    'stories',
    {'cover_image_id': coverImageId},
    where: 'title = ?',
    whereArgs: [title],
  );
}



  static Future<List<String>> getHighlightsOfYear(
    int year, {
    int limit = 20,
  }) async {
    final db = await database;

    final start = DateTime(year, 1, 1).toIso8601String();
    final end = DateTime(year, 12, 31, 23, 59, 59).toIso8601String();

    final results = await db.query(
      'images',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [start, end],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map((e) => e['id'] as String).toList();
  }
}

class DbImage {
  final String id;
  final String path;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final int? faissId;
  final String? labelId;

  DbImage({
    required this.id,
    required this.path,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.faissId,
    this.labelId,
  });

  // Convert Image to a map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'created_at': createdAt.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'faiss_id': faissId,
      'label_id': labelId,
    };
  }

  // Create DbImage from a database map
  static DbImage fromMap(Map<String, dynamic> map) {
    return DbImage(
      id: map['id'] as String,
      path: map['path'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      faissId: map['faiss_id'],
      labelId: map['label_id'] as String?,
    );
  }
}
