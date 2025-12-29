import 'package:flutter/material.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:imgrep/utils/debug_logger.dart';

class CustomImagePicker extends StatefulWidget {
  final Function(List<DbImage>) onImagesSelected;

  const CustomImagePicker({super.key, required this.onImagesSelected});

  @override
  State<CustomImagePicker> createState() => _CustomImagePickerState();
}

class _CustomImagePickerState extends State<CustomImagePicker> {
  final List<String> _selectedImageIds = [];
  final Map<String, DbImage> _imageCache = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialImages();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 1000) {
      ImageService.loadMoreImages();
    }
  }

  Future<void> _loadInitialImages() async {
    if (ImageService.thumbnailCount == 0) {
      await ImageService.loadMoreImages(getUnsyncedImages: true);
    }
  }

  void _toggleSelection(String imageId) {
    setState(() {
      if (_selectedImageIds.contains(imageId)) {
        _selectedImageIds.remove(imageId);
      } else {
        _selectedImageIds.add(imageId);
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedImageIds.isEmpty) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing images...'),
                  ],
                ),
              ),
            ),
          ),
    );

    try {
      final List<DbImage> dbImages = [];

      for (final imageId in _selectedImageIds) {
        if (_imageCache.containsKey(imageId)) {
          dbImages.add(_imageCache[imageId]!);
        } else {
          final DbImage? dbImage = await DatabaseService.getImageById(imageId);
          if (dbImage != null) {
            _imageCache[imageId] = dbImage;
            dbImages.add(dbImage);
          } else {
            Dbg.w('Image not found in database with ID: $imageId');
          }
        }
      }
      
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      Navigator.of(context).pop(); // Close picker
      widget.onImagesSelected(dbImages);
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      Dbg.e('Error processing selected images: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildImageTile(int index) {
    final thumbnail = ImageService.getThumbnail(index);
    final imageId = ImageService.getImageIdByIndex(index);

    if (imageId == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
      );
    }

    final isSelected = _selectedImageIds.contains(imageId);

    return GestureDetector(
      onTap: () => _toggleSelection(imageId),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              thumbnail == null
                  ? Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.grey,
                      size: 24,
                    ),
                  )
                  : Image.memory(thumbnail, fit: BoxFit.cover),
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.blue,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: const Text(
          'Select Images to Sync',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          if (_selectedImageIds.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _selectedImageIds.clear()),
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: ImageService.thumbnailCountNotifier,
        builder: (context, count, _) {
          if (count == 0) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.green,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No unsynced images found',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: count,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) => _buildImageTile(index),
          );
        },
      ),
      floatingActionButton:
          _selectedImageIds.isNotEmpty
              ? FloatingActionButton.extended(
                onPressed: _confirmSelection,
                backgroundColor: Colors.blue,
                icon: const Icon(Icons.sync, color: Colors.white),
                label: Text(
                  'Sync ${_selectedImageIds.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              : null,
    );
  }
}
