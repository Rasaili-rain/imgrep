import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:imgrep/pages/library.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/utils/settings.dart';
import 'package:imgrep/utils/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/*
 * This is a static class that is responsible for handling:
 * - Gallery Event Hook
 * - Image Syncing to the internal database
 * - Provides image for renderings

 * NOTE(slok):
 * - This is initialized during the program startup
 * - The image syncing is done only once for first boot, the rest is handled from event hook system
 */

class ImageService {
  static late final PermissionState _ps;
  static const EventChannel _channel = EventChannel("GALLERY_HOOK_CHANNEL");
  static final Map<String, Uint8List> _thumbnails = {};
  static final List<String> _imageIds = [];
  static int _currentPage = 0;
  static bool _loading = false;

  // Notifiers
  static ValueNotifier<int> thumbnailCountNotifier = ValueNotifier(0);
  static ValueNotifier<double> syncProgressNotifier = ValueNotifier(0);

  // Getters
  static int get thumbnailCount => _thumbnails.length;
  static String getImageId(int index) {
    if (index >= 0 && index < _imageIds.length) {
      return _imageIds[index];
    }
    throw RangeError('Index out of bounds: $index');
  }

  static Uint8List? getThumbnail(int index) {
    if (index >= _imageIds.length) return null;

    final String id = _imageIds[index];
    return _thumbnails[id];
  }

  static Future<Uint8List?> getThumbnailById(String id) async {
    if (_thumbnails.containsKey(id)) {
      return _thumbnails[id];
    }

    final AssetEntity? asset = await AssetEntity.fromId(id);

    if (asset == null) {
      Dbg.e("Failed to load asset with id: $id");
      return null;
    }

    // Creating a thumbnail from that asset
    final Uint8List? thumbnailData = await asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
    );

    if (thumbnailData == null) {
      Dbg.e("Failed to load thumbnail data of id: $id");
      return null;
    }

    // Adding it to the map of thumbnails and also increasing the notifier value
    _thumbnails[id] = thumbnailData;

    // Making sure there wont be duplicate ids
    _imageIds.remove(id);
    _imageIds.add(id);

    return thumbnailData;
  }

  /*
   * Initializes the permissions for the image handling
   * And also starts the gallery listening channel
   */

  static Future<void> init() async {
    _ps = await PhotoManager.requestPermissionExtend();
    if (!_ps.hasAccess) {
      Dbg.e(
        "Photo permission denied, Stoping further initialization of ImageService",
      );
      return;
    }
    ImageService._listen();
  }

  /*
   * Function that handles the event from gallery
   * Responsible for deleting and updating the image database whenever image is deleted or added
   */

  static Future<void> _handleGalleryEvent(dynamic event) async {
    if (event is Map) {
      final type = event["type"] as String?;
      final id = event["id"] as String?;

      if (type == null) return;

      // Handling deletion of image
      if (type == "DELETE" && id != null) {
        // If the image is in the memory delete it from there
        if (_thumbnails.containsKey(id)) {
          _thumbnails.remove(id);
          _imageIds.remove(id);
          thumbnailCountNotifier.value = _thumbnails.length;
        }

        // Deleting the image from the database
        await DatabaseService.deleteImage(id);
      }
      // Handling update of image
      else if (type == "UPDATE" && id != null) {
        // Loading the thumbnail for the new/updated image
        final AssetEntity? asset = await AssetEntity.fromId(id);

        if (asset == null) {
          Dbg.e("Failed to load asset with id: $id");
          return;
        }

        final Uint8List? thumbnailData = await asset.thumbnailDataWithSize(
          const ThumbnailSize(200, 200),
        );
        if (thumbnailData == null) {
          Dbg.e("Failed to load thumbnail data of id: $id");
          return;
        }

        // Storing the thumbnail to the memory
        _thumbnails[id] = thumbnailData;

        // Removing the id if already existed and inserting into the top so the new image renders in first
        _imageIds.remove(id);
        _imageIds.insert(0, id);

        thumbnailCountNotifier.value = _thumbnails.length;

        // Inserting/Replacing the new image in the database
        await DatabaseService.insertImage(asset);
      }
    }
  }

  // Gallery event listener
  static void _listen() {
    _channel.receiveBroadcastStream().listen((event) {
      Dbg.i(event);
      _handleGalleryEvent(event);
    });
  }

  /*
   * Function to collect all the images from gallery and stores in the database
   * This only occurs once we install this application
   */

  static Future<void> syncGalleryImages() async {
    // Loading a single album with all of the images from device
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    final AssetPathEntity album = albums.first;
    final int maxAssets = await album.assetCountAsync;

    // Getting the list of images from album
    final List<AssetEntity> images = await album.getAssetListRange(
      start: 0,
      end: maxAssets,
    );

    // Storing it into the database
    final List<List<AssetEntity>> batches = chunkList(
      images,
      Settings.batchSize,
    );
    int i = 1;
    for (var batch in batches) {
      await DatabaseService.batchInsertImage(batch);

      i += batch.length;
      syncProgressNotifier.value = i / maxAssets;
    }

    final Map<String, List<AssetEntity>> groups = {};
    for (final img in images) {
      final date = img.createDateTime;
      final id = DateFormat('yyyy-MM').format(date);
      groups.putIfAbsent(id, () => []).add(img);
    }

    for (final entry in groups.entries) {
      final List<AssetEntity> groupAssets = entry.value;
      final title = DateFormat(
        'MMMM yyyy',
      ).format(groupAssets.first.createDateTime);
      final imageIds = groupAssets.map((e) => e.id).toList();
      final coverId = imageIds.first;
      final description = generateStoryDescription(title, imageIds.length);

      await DatabaseService.insertStory(
        id: entry.key,
        title: title,
        description: description,
        imageIds: imageIds,
        coverImageId: coverId,
        createdAt: groupAssets.first.createDateTime,
      );
    }
  }

  /*
   * This function is responsible to load the image from database and store its thumbnails.
   */

  static Future<void> loadMoreImages({
    int amount = Settings.pageSize,
    bool getUnsyncedImages = false,
  }) async {
    if (_loading) return;
    _loading = true;

    // Get the image ids from the database
    List<DbImage> images;
    if (getUnsyncedImages) {
      images = await DatabaseService.getUnsyncedImagesPaginated(
        _currentPage,
        amount,
      );
    } else {
      images = await DatabaseService.getImagesPaginated(_currentPage, amount);
    }

    _currentPage += images.length;

    for (var img in images) {
      var id = img.id;
      // Loading the full asset
      final AssetEntity? asset = await AssetEntity.fromId(id);

      if (asset == null) {
        Dbg.e("Failed to load asset with id: $id");
        continue;
      }

      // Creating a thumbnail from that asset
      final Uint8List? thumbnailData = await asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
      );
      if (thumbnailData == null) {
        Dbg.e("Failed to load thumbnail data of id: $id");
        continue;
      }

      // Adding it to the map of thumbnails and also increasing the notifier value
      _thumbnails[id] = thumbnailData;

      // Making sure there wont be duplicate ids
      _imageIds.remove(id);
      _imageIds.add(id);

      thumbnailCountNotifier.value = _thumbnails.length;
    }

    // Loading is complete
    _loading = false;
  }

  static Future<void> incrementalSync() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncedStr = prefs.getString('lastSyncedAt');
    final lastSynced =
        lastSyncedStr != null ? DateTime.tryParse(lastSyncedStr) : null;

    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) return;

    final AssetPathEntity album = albums.first;

    // Check only recent 100 images
    final List<AssetEntity> recentAssets = await album.getAssetListRange(
      start: 0,
      end: 100,
    );

    for (final asset in recentAssets) {
      if (lastSynced == null || asset.createDateTime.isAfter(lastSynced)) {
        final id = asset.id;

        // Store thumbnail
        final thumb = await asset.thumbnailDataWithSize(
          const ThumbnailSize(200, 200),
        );
        if (thumb == null) continue;

        _thumbnails[id] = thumb;

        _imageIds.remove(id);
        _imageIds.insert(0, id);

        thumbnailCountNotifier.value = _thumbnails.length;

        await DatabaseService.insertImage(asset);
      }

      final Map<String, List<AssetEntity>> groups = {};
      for (final img in recentAssets) {
        final date = img.createDateTime;
        final id = DateFormat('yyyy-MM').format(date);
        groups.putIfAbsent(id, () => []).add(img);
      }
      for (final entry in groups.entries) {
        final List<AssetEntity> groupAssets = entry.value;
        final title = DateFormat(
          'MMMM yyyy',
        ).format(groupAssets.first.createDateTime);
        final imageIds = groupAssets.map((e) => e.id).toList();
        await DatabaseService.updateStory(title: title, newImageIds: imageIds, coverImageId: imageIds.first);
      }
     
         }

    // Update last synced timestamp
    await prefs.setString('lastSyncedAt', DateTime.now().toIso8601String());
  }

  static Future<Map<String, String>?> getMetadata(int index) async {
    if (index < 0 || index >= _imageIds.length) return null;

    final String id = _imageIds[index];
    final AssetEntity? asset = await AssetEntity.fromId(id);
    if (asset == null) return null;

    final String name = asset.title ?? 'Unknown';
    final String date = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(asset.createDateTime);
    final String resolution = '${asset.width} x ${asset.height}';

    return {'Filename': name, 'Date': date, 'Resolution': resolution};
  }

  static String? getImageIdByIndex(int index) {
    if (index >= 0 && index < _imageIds.length) {
      return _imageIds[index];
    }
    return null;
  }
}
