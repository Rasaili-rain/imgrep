import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:imgrep/utils/debug_logger.dart';

class SearchImageViewerWidget extends StatefulWidget {
  final int initialIndex;
  final List<String> imageIds;

  const SearchImageViewerWidget({
    required this.initialIndex,
    required this.imageIds,
    super.key,
  });

  @override
  State<SearchImageViewerWidget> createState() => _SearchImageViewerWidgetState();
}

class _SearchImageViewerWidgetState extends State<SearchImageViewerWidget> {
  late final PageController _pageController;
  late final ScrollController _thumbnailScrollController;
  int currentIndex = 0;

  // Cache for full resolution images
  final Map<String, Uint8List> _fullResImageCache = {};
  final Map<String, bool> _loadingImages = {};

  static const int thumbnailsPerPage = 8;

  @override
  void initState() {
    _pageController = PageController(initialPage: widget.initialIndex);
    _thumbnailScrollController = ScrollController();
    currentIndex = widget.initialIndex;
    
    // Preload current and adjacent images
    _getFullResolutionImage(widget.imageIds[widget.initialIndex]);
    _preloadAdjacentImages();
    
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _getFullResolutionImage(String imageId) async {
    // Return cached image if available
    if (_fullResImageCache.containsKey(imageId)) {
      return _fullResImageCache[imageId];
    }

    // Check if already loading
    if (_loadingImages[imageId] == true) {
      // Wait for loading to complete
      while (_loadingImages[imageId] == true) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _fullResImageCache[imageId];
    }

    // Start loading
    _loadingImages[imageId] = true;
    
    try {
      final AssetEntity? asset = await AssetEntity.fromId(imageId);
      if (asset == null) {
        Dbg.e("Failed to load asset with id: $imageId");
        return null;
      }

      // Get full resolution image data
      final Uint8List? fullResData = await asset.originBytes;
      
      if (fullResData != null) {
        _fullResImageCache[imageId] = fullResData;
        _limitCacheSize();
        return fullResData;
      }
    } catch (e) {
      Dbg.e("Error loading full resolution image: $e");
    } finally {
      _loadingImages[imageId] = false;
    }
    
    return null;
  }

  void _limitCacheSize() {
    // Keep only 10 images in cache to prevent memory issues
    if (_fullResImageCache.length > 10) {
      final keys = _fullResImageCache.keys.toList();
      final keysToRemove = keys.take(_fullResImageCache.length - 10);
      for (final key in keysToRemove) {
        _fullResImageCache.remove(key);
      }
    }
  }

  void _preloadAdjacentImages() {
    final total = widget.imageIds.length;
    
    // Preload previous image
    if (currentIndex > 0) {
      _getFullResolutionImage(widget.imageIds[currentIndex - 1]);
    }
    
    // Preload next image
    if (currentIndex < total - 1) {
      _getFullResolutionImage(widget.imageIds[currentIndex + 1]);
    }
  }

  List<int> _getThumbnailIndices() {
    final total = widget.imageIds.length;

    int start = (currentIndex - thumbnailsPerPage ~/ 2).clamp(0, total - 1);
    int end = (start + thumbnailsPerPage).clamp(0, total);

    if (end - start < thumbnailsPerPage && start > 0) {
      start = (end - thumbnailsPerPage).clamp(0, total - 1);
    }

    return List.generate(end - start, (i) => start + i);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageIds.length;
    final thumbnailIndices = _getThumbnailIndices();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '${currentIndex + 1} of $total',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),

          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: (index) {
                setState(() => currentIndex = index);
                _preloadAdjacentImages();
              },
              itemBuilder: (context, index) {
                final imageId = widget.imageIds[index];

                return FutureBuilder<Uint8List?>(
                  future: _getFullResolutionImage(imageId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Show thumbnail while loading full resolution
                      return FutureBuilder(
                        future: ImageService.getThumbnailById(imageId),
                        builder: (context, thumbSnapshot) {
                          if (thumbSnapshot.hasData && thumbSnapshot.data != null) {
                            return Stack(
                              children: [
                                PhotoView(
                                  imageProvider: MemoryImage(thumbSnapshot.data!),
                                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                                ),
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ],
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          );
                        },
                      );
                    }

                    if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                      // Fallback to thumbnail if full resolution fails
                      return FutureBuilder(
                        future: ImageService.getThumbnailById(imageId),
                        builder: (context, thumbSnapshot) {
                          if (thumbSnapshot.hasData && thumbSnapshot.data != null) {
                            return PhotoView(
                              imageProvider: MemoryImage(thumbSnapshot.data!),
                              backgroundDecoration: const BoxDecoration(color: Colors.black),
                            );
                          }
                          return const Center(
                            child: Icon(Icons.error, color: Colors.white, size: 40),
                          );
                        },
                      );
                    }

                    // Display full resolution image
                    return PhotoView(
                      imageProvider: MemoryImage(snapshot.data!),
                      backgroundDecoration: const BoxDecoration(color: Colors.black),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3.0,
                    );
                  },
                );
              },
            ),
          ),

          Container(
            height: 80,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              controller: _thumbnailScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: thumbnailIndices.length,
              itemBuilder: (context, listIndex) {
                final imageIndex = thumbnailIndices[listIndex];
                final imageId = widget.imageIds[imageIndex];
                final isSelected = imageIndex == currentIndex;

                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      imageIndex,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: isSelected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 2)
                          : Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: FutureBuilder(
                      future: ImageService.getThumbnailById(imageId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasError || snapshot.data == null) {
                          return Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.image, size: 30, color: Colors.grey),
                          );
                        }

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            snapshot.data!,
                            height: 60,
                            width: 60,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}