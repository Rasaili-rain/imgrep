import 'package:flutter/material.dart';
import 'package:imgrep/services/api/upload_image.dart';
import 'package:imgrep/services/api/user.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/utils/settings.dart';
import 'package:imgrep/widgets/custom_image_picker.dart';

class SyncManager extends ChangeNotifier {
  static bool _isSyncing = false;
  static bool _shouldStopSync = false;
  static int _syncProgress = 0;
  static int _totalItems = 0;

  static bool get isSyncing => _isSyncing;
  static bool get shouldStopSync => _shouldStopSync;
  static int get syncProgress => _syncProgress;
  static int get totalItems => _totalItems;
  static double get progressPercentage =>
      _totalItems > 0 ? _syncProgress / _totalItems : 0.0;

  static final SyncManager _instance = SyncManager._internal();
  SyncManager._internal();
  factory SyncManager() => _instance;

  static void _updateSyncState({
    bool? syncing,
    int? progress,
    int? total,
    bool? shouldStop,
  }) {
    if (syncing != null) _isSyncing = syncing;
    if (progress != null) _syncProgress = progress;
    if (total != null) _totalItems = total;
    if (shouldStop != null) _shouldStopSync = shouldStop;
    _instance.notifyListeners();
  }

  static void startSync(int totalItems) => _updateSyncState(
    syncing: true,
    progress: 0,
    total: totalItems,
    shouldStop: false,
  );

  static void updateProgress(int currentProgress) =>
      _updateSyncState(progress: currentProgress);

  static void stopSync() => _updateSyncState(shouldStop: true);

  static void finishSync() => _updateSyncState(
    syncing: false,
    progress: 0,
    total: 0,
    shouldStop: false,
  );
}

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  SyncPageState createState() => SyncPageState();
}

class SyncPageState extends State<SyncPage> {
  int _selectedImageCount = 0;
  Map<String, int>? _syncStats;

  @override
  void initState() {
    super.initState();
    SyncManager().addListener(_onSyncStateChanged);
    _loadSyncStats();
  }

  @override
  void dispose() {
    SyncManager().removeListener(_onSyncStateChanged);
    super.dispose();
  }

  void _onSyncStateChanged() => setState(() {});
  Future<void> _loadSyncStats() async {
    try {
      final stats = await DatabaseService.getSyncStats();
      setState(() => _syncStats = stats);
    } catch (e) {
      Dbg.e('Error loading sync stats: $e');
    }
  }

  Future<void> _syncImages(List<DbImage> images) async {
    if (images.isEmpty) {
      _showMessage('No images to sync');
      return;
    }

    SyncManager.startSync(images.length);

    try {
      final userId = await UserManager.getUserId();
      if (userId == null) throw Exception('User not authenticated');

      int successCount = 0;
      int failureCount = 0;

      for (int i = 0; i < images.length; i++) {
        // Check if sync should be stopped
        if (SyncManager.shouldStopSync) {
          Dbg.i('Sync stopped by user at ${i + 1}/${images.length}');
          _showMessage(
            'Sync stopped. Synced $successCount/${images.length} images.',
            isError: true,
          );
          break;
        }

        final image = images[i];

        try {
          Dbg.i('Syncing image ${i + 1}/${images.length}: ${image.path}');

          if (image.faissId != null) {
            Dbg.i('Image ${image.id} already synced, skipping');
            successCount++;
            SyncManager.updateProgress(i + 1);
            continue;
          }

          final result = await uploadImage(
            image.path,
            userId,
            Settings.serverIp,
            image.createdAt,
            image.latitude,
            image.longitude,
          );

          if (result != null &&
              result["index"] != null &&
              result["message"] != null) {
            final faissId = result["index"].toString();
            final labelId = result["label_id"].toString();

            // Use the image ID from our database, not the returned one
            await DatabaseService.updateFaissIndex(image.id, faissId);
            await DatabaseService.updateLabelId(image.id, labelId);
            successCount++;

            Dbg.i(
              'Successfully synced image ${image.id} with faiss ID $faissId',
            );
          } else {
            failureCount++;
            Dbg.w(
              'Failed to sync image ${image.id}: Invalid response from server',
            );
            await DatabaseService.markImageAsUnsynced(image.id);
          }
        } catch (e) {
          failureCount++;
          Dbg.e('Error syncing image ${image.id}: $e');
          await DatabaseService.markImageAsUnsynced(image.id);
        }

        SyncManager.updateProgress(i + 1);
      }

      // Show detailed results only if sync wasn't stopped
      if (!SyncManager.shouldStopSync) {
        if (failureCount == 0) {
          _showMessage('Successfully synced all $successCount images!');
        } else {
          _showMessage(
            'Synced $successCount/${images.length} images ($failureCount failed)',
            isError: failureCount > successCount,
          );
        }
      }
    } catch (e) {
      Dbg.e('Sync error: $e');
      _showMessage('Sync failed: $e', isError: true);
    } finally {
      SyncManager.finishSync();
    }
  }

  Future<void> _showSyncConfirmationDialog(
    List<DbImage> imagesToSync, {
    bool isSelectedImages = true,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.sync, color: Colors.blue[400], size: 24),
              const SizedBox(width: 12),
              Text(
                'Confirm Sync',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSelectedImages
                    ? 'Proceed with syncing ${imagesToSync.length} selected image${imagesToSync.length == 1 ? '' : 's'}?'
                    : 'Proceed with syncing all ${imagesToSync.length} unsynced image${imagesToSync.length == 1 ? '' : 's'}?',
                style: TextStyle(color: Colors.grey[300], fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[400], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will upload secure embeddings to enable fast image search.',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _syncImages(imagesToSync);

      // Reload stats after sync if it was for all unsynced images
      if (!isSelectedImages) await _loadSyncStats();
    } else if (isSelectedImages) {
      // Reset selected image count if user cancels selected images sync
      setState(() => _selectedImageCount = 0);
    }
  }

  Future<void> _pickAndSyncImages() async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (context) => CustomImagePicker(
                onImagesSelected: (List<DbImage> selectedImages) async {
                  if (selectedImages.isEmpty) {
                    _showMessage(
                      'No valid images found in database',
                      isError: true,
                    );
                    return;
                  }
                  setState(() => _selectedImageCount = selectedImages.length);
                  // Show sync confirmation dialog with the selected images
                  await _showSyncConfirmationDialog(
                    selectedImages,
                    isSelectedImages: true,
                  );
                },
              ),
        ),
      );
    } catch (e) {
      _showMessage('Error selecting images: $e', isError: true);
      setState(() => _selectedImageCount = 0);
    }
  }

  Future<void> _syncAllUnsyncedImages() async {
    try {
      final unsyncedImages = await _getUnsyncedImages();
      if (unsyncedImages.isEmpty) {
        _showMessage('All images are already synced!');
        return;
      }

      Dbg.i('Found ${unsyncedImages.length} unsynced images');
      await _showSyncConfirmationDialog(
        unsyncedImages,
        isSelectedImages: false,
      );

      // Reload stats after sync (only if sync was confirmed and completed)
      if (!SyncManager.isSyncing) {
        await _loadSyncStats();
      }
    } catch (e) {
      Dbg.e('Error syncing all images: $e');
      _showMessage('Error syncing all images: $e', isError: true);
    }
  }

  Future<List<DbImage>> _getUnsyncedImages() async {
    const int pageSize = 100;
    int currentPage = 0;
    List<DbImage> allUnsyncedImages = [];

    while (true) {
      final images = await DatabaseService.getUnsyncedImages(
        offset: currentPage * pageSize,
        limit: pageSize,
      );

      if (images.isEmpty) break;

      allUnsyncedImages.addAll(images);
      currentPage++;

      // Safety check to prevent infinite loops
      if (allUnsyncedImages.length > 10000) {
        Dbg.w('Retrieved maximum limit of unsynced images (10000)');
        break;
      }
    }

    return allUnsyncedImages;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red[700] : Colors.green[700],
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Sync'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Privacy notice
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.green[400], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your privacy matters. We only store secure embeddings for fast image search, never the images themselves.',
                        style: TextStyle(
                          color: Colors.grey[300],
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Sync stats
              if (_syncStats != null) _buildSyncStats(),

              const SizedBox(height: 40),
              _buildSyncStatus(),
              const SizedBox(height: 32),
              _buildActionButtons(),

              // Selected images info
              if (_selectedImageCount > 0) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue[700]!),
                  ),
                  child: Text(
                    'Selected: $_selectedImageCount images',
                    style: TextStyle(
                      color: Colors.blue[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStats() {
    final stats = _syncStats!;
    final total = stats['total'] ?? 0;
    final synced = stats['synced'] ?? 0;
    final unsynced = stats['unsynced'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        children: [
          Text(
            'Sync Statistics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Total', total.toString(), Colors.blue[400]!),
              _buildStatItem('Synced', synced.toString(), Colors.green[400]!),
              _buildStatItem(
                'Unsynced',
                unsynced.toString(),
                unsynced > 0 ? Colors.orange[400]! : Colors.grey[500]!,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ],
    );
  }

  Widget _buildSyncStatus() {
    if (SyncManager.isSyncing) {
      return Column(
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: SyncManager.progressPercentage,
              strokeWidth: 6,
              color: Colors.white,
              backgroundColor: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Syncing Images...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${SyncManager.syncProgress}/${SyncManager.totalItems}',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.green[900]?.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green[700]!, width: 2),
          ),
          child: Icon(Icons.cloud_done, color: Colors.green[400], size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          'Ready to Sync',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final bool isDisabled = SyncManager.isSyncing;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: isDisabled ? null : _pickAndSyncImages,
            icon: const Icon(Icons.photo_library),
            label: const Text('Sync Selected Images'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.grey[800],
              disabledForegroundColor: Colors.grey[600],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: isDisabled ? null : _syncAllUnsyncedImages,
            icon: const Icon(Icons.sync),
            label: const Text('Sync All Unsynced'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.grey[600],
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
