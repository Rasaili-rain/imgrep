import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:imgrep/services/database_service.dart';
import 'dart:developer' as developer;

class PersonPhotosPage extends StatefulWidget {
  final String personId;
  final String personName;
  final AssetEntity? coverPhoto;

  const PersonPhotosPage({
    super.key,
    required this.personId,
    required this.personName,
    this.coverPhoto,
  });

  @override
  State<PersonPhotosPage> createState() => _PersonPhotosPageState();
}

class _PersonPhotosPageState extends State<PersonPhotosPage> {
  List<AssetEntity> personPhotos = [];
  bool isLoading = true;
  int totalPhotos = 0;

  @override
  void initState() {
    super.initState();
    loadPersonPhotos();
  }

  Future<void> loadPersonPhotos() async {
    try {
      setState(() {
        isLoading = true;
      });

      final images = await DatabaseService.getImagesForLabel(widget.personId);
      developer.log('Images found for person ${widget.personName}: ${images.length}', name: 'PersonPhotosPage');

      List<AssetEntity> assets = [];
      for (int i = 0; i < images.length; i++) {
        final img = images[i];
        developer.log('Processing image ${i + 1}/${images.length}: ID=${img.id}', name: 'PersonPhotosPage');

        try {
          final asset = await AssetEntity.fromId(img.id);
          if (asset != null) {
            assets.add(asset);
            developer.log('Successfully loaded asset ${assets.length}', name: 'PersonPhotosPage');
          } else {
            developer.log('Asset is null for image ID: ${img.id}', name: 'PersonPhotosPage');
          }
        } catch (assetError) {
          developer.log('Error loading asset for image ID ${img.id}: $assetError', name: 'PersonPhotosPage');
        }
      }

      developer.log('Final assets loaded: ${assets.length}', name: 'PersonPhotosPage');

      setState(() {
        personPhotos = assets;
        totalPhotos = assets.length;
        isLoading = false;
      });
    } catch (e) {
      developer.log('Error loading person photos: $e', name: 'PersonPhotosPage');
      setState(() {
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading photos: ${e.toString()}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  void _openPhoto(AssetEntity asset, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoViewPage(
          assets: personPhotos,
          initialIndex: index,
          personName: widget.personName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.personName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (!isLoading)
              Text(
                '$totalPhotos ${totalPhotos == 1 ? 'photo' : 'photos'}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
          : personPhotos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No photos found for this person',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(4.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: personPhotos.length,
                  itemBuilder: (context, index) {
                    final asset = personPhotos[index];
                    return GestureDetector(
                      onTap: () => _openPhoto(asset, index),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AssetEntityImage(
                                asset,
                                isOriginal: false,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    color: Colors.grey[900],
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[900],
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                      size: 32,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class PhotoViewPage extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final String personName;

  const PhotoViewPage({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.personName,
  });

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  late PageController _pageController;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${currentIndex + 1} of ${widget.assets.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.assets.length,
        onPageChanged: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final asset = widget.assets[index];
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: AssetEntityImage(
                asset,
                isOriginal: true,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
