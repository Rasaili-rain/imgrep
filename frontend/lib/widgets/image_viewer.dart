import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:imgrep/services/api/upload_image.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:photo_view/photo_view.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:photo_manager/photo_manager.dart';

class ImageViewerWidget extends StatefulWidget {
  final int initialIndex;
  const ImageViewerWidget({super.key, required this.initialIndex});

  @override
  State<ImageViewerWidget> createState() => _ImageViewerWidgetState();
}

class _ImageViewerWidgetState extends State<ImageViewerWidget> {
  late final PageController _pageController;
  late final ScrollController _thumbnailScrollController;
  int currentIndex = 0;
  bool _showMetadata = false;
  String caption = '';

  // Cache for full resolution images
  final Map<String, Uint8List> _fullResImageCache = {};
  final Map<String, bool> _loadingImages = {};

  // Thumbnail dimensions and spacing
  static const double thumbnailWidth = 60.0;
  static const double thumbnailMargin = 4.0;
  static const double totalThumbnailWidth = thumbnailWidth + (thumbnailMargin * 2);

  Future<String> getCaptionById(String id) async {
    caption = (await getCaption(id));
    Dbg.i(caption);
    return caption;
  }

  Future<Uint8List?> _getFullResolutionImage(int index) async {
    final String? imageId = ImageService.getImageIdByIndex(index);
    if (imageId == null) return null;

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
        return fullResData;
      }
    } catch (e) {
      Dbg.e("Error loading full resolution image: $e");
    } finally {
      _loadingImages[imageId] = false;
    }

    return null;
  }

  void _preloadAdjacentImages() {
    // Preload previous and next images
    final total = ImageService.thumbnailCount;

    if (currentIndex > 0) {
      _getFullResolutionImage(currentIndex - 1);
    }
    if (currentIndex < total - 1) {
      _getFullResolutionImage(currentIndex + 1);
    }
  }

  void _scrollThumbnailToCenter(int index) {
    if (!_thumbnailScrollController.hasClients) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final centerPosition = (index * totalThumbnailWidth) - (screenWidth / 2) + (totalThumbnailWidth / 2);

    _thumbnailScrollController.animateTo(
      centerPosition.clamp(0.0, _thumbnailScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: currentIndex);
    _thumbnailScrollController = ScrollController();

    // Preload current and adjacent images
    _getFullResolutionImage(currentIndex);
    _preloadAdjacentImages();

    // Center the thumbnail after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollThumbnailToCenter(currentIndex);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    super.dispose();
  }

  void _toggleMetadata(bool show) {
    setState(() => _showMetadata = show);
  }

  @override
  Widget build(BuildContext context) {
    final total = ImageService.thumbnailCount;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < -200) {
                  _toggleMetadata(true); // Swipe up
                } else if (details.primaryVelocity! > 200) {
                  _toggleMetadata(false); // Swipe down
                }
              }
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: (index) {
                setState(() {
                  currentIndex = index;
                  _showMetadata = false;
                });

                // Scroll thumbnail to center when page changes
                _scrollThumbnailToCenter(index);

                // Preload adjacent images when page changes
                _preloadAdjacentImages();
              },
              itemBuilder: (context, index) {
                return FutureBuilder<Uint8List?>(
                  future: _getFullResolutionImage(index),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Show thumbnail while loading full resolution
                      final thumbnail = ImageService.getThumbnail(index);
                      if (thumbnail != null) {
                        return Stack(
                          children: [
                            PhotoView(
                              imageProvider: MemoryImage(thumbnail),
                              backgroundDecoration: const BoxDecoration(
                                color: Colors.black,
                              ),
                            ),
                            const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          ],
                        );
                      } else {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      }
                    }

                    if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                      // Fallback to thumbnail if full resolution fails
                      final thumbnail = ImageService.getThumbnail(index);
                      if (thumbnail != null) {
                        return PhotoView(
                          imageProvider: MemoryImage(thumbnail),
                          backgroundDecoration: const BoxDecoration(
                            color: Colors.black,
                          ),
                        );
                      }

                      return const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 40,
                        ),
                      );
                    }

                    // Display full resolution image
                    return PhotoView(
                      imageProvider: MemoryImage(snapshot.data!),
                      backgroundDecoration: const BoxDecoration(
                        color: Colors.black,
                      ),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3.0,
                    );
                  },
                );
              },
            ),
          ),

          if (!_showMetadata)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 70,
                child: ListView.builder(
                  controller: _thumbnailScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: total,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemBuilder: (context, i) {
                    final thumb = ImageService.getThumbnail(i);
                    final isSelected = i == currentIndex;

                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: thumbnailMargin),
                        padding: isSelected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white30,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: thumb == null
                            ? Container(
                                height: thumbnailWidth,
                                width: thumbnailWidth,
                                color: Colors.grey.shade800,
                                child: const Icon(
                                  Icons.image,
                                  color: Colors.white38,
                                ),
                              )
                            : Image.memory(
                                thumb,
                                height: thumbnailWidth,
                                width: thumbnailWidth,
                                fit: BoxFit.cover,
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Metadata Panel
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            bottom: _showMetadata ? 0 : -220,
            left: 0,
            right: 0,
            height: 220,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: FutureBuilder<List<dynamic>>(
                future: Future.wait([
                  ImageService.getMetadata(currentIndex),
                  getCaptionById(
                    ImageService.getImageId(currentIndex),
                  ),
                ]),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  final metadata = snapshot.data![0] as Map<String, String>;
                  final caption = snapshot.data![1] as String;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Image Details",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...metadata.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Caption",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        caption,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
