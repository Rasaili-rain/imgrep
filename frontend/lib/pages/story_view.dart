import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:imgrep/widgets/app_bar.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class StoryViewPage extends StatefulWidget {
  final String storyId;

  const StoryViewPage({super.key, required this.storyId});

  @override
  State<StoryViewPage> createState() => _StoryViewPageState();
}

class _StoryViewPageState extends State<StoryViewPage> {
  late final PageController _pageController;
  late final ScrollController _thumbScrollController;

  List<AssetEntity> assets = [];
  bool isLoading = true;
  int _currentIndex = 0;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _thumbScrollController = ScrollController();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final db = await DatabaseService.database;

    final rows = await db.query(
      'stories',
      where: 'id = ?',
      whereArgs: [widget.storyId],
      limit: 1,
    );

    if (rows.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    final row = rows.first;
    final List<String> imageIds = List<String>.from(
      jsonDecode(row['image_ids'] as String),
    );
    final List<AssetEntity> loadedAssets = [];

    for (final id in imageIds) {
      final asset = await AssetEntity.fromId(id);
      if (asset != null) loadedAssets.add(asset);
    }

    setState(() {
      assets = loadedAssets;
      isLoading = false;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbScrollController.dispose();
    super.dispose();
  }

  void _jumpToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _thumbScrollController.hasClients) {
        _scrollThumbnailToCenter(index);
      }
    });
  }

  void _scrollThumbnailToCenter(int index) {
    final double itemWidth = 80;
    final double spacing = 0;
    final double screenWidth = MediaQuery.of(context).size.width;

    final double targetOffset =
        (itemWidth + spacing) * index - screenWidth / 2 + itemWidth / 2;

    _thumbScrollController.animateTo(
      targetOffset.clamp(
        _thumbScrollController.position.minScrollExtent,
        _thumbScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showUI ? ImGrepAppBar() : null,
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                children: [
                  GestureDetector(
                    onTap: _toggleUI,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: assets.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _thumbScrollController.hasClients) {
                            _scrollThumbnailToCenter(index);
                          }
                        });
                      },
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        return Center(
                          child: Hero(
                            tag: '${widget.storyId}-$index',
                            child: AssetEntityImage(
                              asset,
                              isOriginal: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 👇 Animated bottom bar
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    left: 0,
                    right: 0,
                    bottom: _showUI ? 30 : -100,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.black,
                      child: SizedBox(
                        height: 80,
                        child: ListView.builder(
                          controller: _thumbScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: assets.length,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemBuilder: (context, index) {
                            final asset = assets[index];
                            final isSelected = index == _currentIndex;

                            return GestureDetector(
                              onTap: () => _jumpToPage(index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? Colors.white
                                              : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: AssetEntityImage(
                                      asset,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      isOriginal: false,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
