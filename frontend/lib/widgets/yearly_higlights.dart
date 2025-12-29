import 'package:flutter/material.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class YearHighlightsWidget extends StatefulWidget {
  const YearHighlightsWidget({super.key});
  @override
  State<YearHighlightsWidget> createState() => _YearHighlightsWidgetState();
}

class _YearHighlightsWidgetState extends State<YearHighlightsWidget> {
  List<AssetEntity> highlights = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadHighlights();
  }

  Future<void> loadHighlights() async {
    final now = DateTime.now();
    final lastYear = now.year - 1;

    final List<String> imageIds = await DatabaseService.getHighlightsOfYear(
      lastYear,
    );

    final List<AssetEntity> assets = [];
    for (final id in imageIds) {
      final asset = await AssetEntity.fromId(id);
      if (asset != null) assets.add(asset);
    }

    setState(() {
      highlights = assets;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (highlights.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            "Highlights from Last Year",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16),
            itemCount: highlights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final asset = highlights[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AssetEntityImage(
                  asset,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  isOriginal: false,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
