import 'package:flutter/material.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:imgrep/widgets/image_viewer.dart';

class HomeScreen extends StatelessWidget {
  final _scrollController = ScrollController();

  HomeScreen({super.key}) {
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 1000) {
      ImageService.loadMoreImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      // NOTE(slok): Listening to the thumbnailCountNotifier variable
      // This widget updates whenever new thumbnail is added
      valueListenable: ImageService.thumbnailCountNotifier,
      builder: (context, count, _) {
        // Rendering loading screen if no image is present
        if (count == 0) {
          return const Center(child: CircularProgressIndicator());
        }
        // Rendering the image grid
        return GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(4),
          itemCount: ImageService.thumbnailCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final thumbnail = ImageService.getThumbnail(index);

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageViewerWidget(
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumbnail == null
                    ? const Icon(
                        Icons.error_outline,
                        color: Colors.grey,
                        size: 32,
                      )
                    : Image.memory(thumbnail, fit: BoxFit.cover),
              ),
            );
          },
        );
      },
    );
  }
}
