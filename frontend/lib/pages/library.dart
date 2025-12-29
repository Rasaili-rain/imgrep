import 'dart:math';

import 'package:flutter/material.dart';
import 'package:imgrep/pages/story_view.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/widgets/yearly_higlights.dart';
import 'package:imgrep/services/api/label.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:imgrep/widgets/person_photo_widget.dart';
import 'package:imgrep/pages/person_photo_page.dart';

class Story {
  final String id;
  final String title;
  final List<AssetEntity> assets;

  Story({required this.id, required this.title, required this.assets});
}

class PersonData {
  final String id;
  final String name;
  final String? imageUrl;
  final String? imagePath;
  final AssetEntity? coverPhoto;
  final int photoCount;

  PersonData({
    required this.id,
    required this.name,
    this.imageUrl,
    this.imagePath,
    this.coverPhoto,
    this.photoCount = 0,
  });
}

Future<List<Story>> loadStoriesFromDB() async {
  final db = await DatabaseService.database;
  final rows = await db.query('stories', orderBy: 'created_at DESC');

  List<Story> stories = [];
  for (final row in rows) {
    final String title = row['title'] as String;
    final String coverId = row['cover_image_id'] as String;

    final AssetEntity? cover = await AssetEntity.fromId(coverId);
    if (cover == null) continue;

    // Load only the cover image, not full list yet
    stories.add(Story(id: row['id'] as String, title: title, assets: [cover]));
  }

  return stories;
}

Future<List<PersonData>> loadPeopleFromDB() async {
  final images = await DatabaseService.getImagesWithDistinctLabels();

  final uniqueLabelIds = <String>{};
  for (final img in images) {
    if (img.labelId != null && img.labelId != "null") {
      uniqueLabelIds.add(img.labelId!);
    }
  }

  List<PersonData> people = [];

  for (final labelId in uniqueLabelIds) {
    Dbg.i('Processing label: $labelId');

    try {
      final label = await getLabelById(labelId) ?? "Unknown";
      final count = await DatabaseService.getImageCountForLabel(labelId);

      // Get the first image for this label as cover photo
      final coverImageData = images.firstWhere(
        (img) => img.labelId == labelId,
        orElse: () => images.first, // fallback
      );

      final AssetEntity? cover = await AssetEntity.fromId(coverImageData.id);

      Dbg.i('Person: $label, Count: $count, Cover loaded: ${cover != null}');

      people.add(PersonData(
        id: labelId,
        name: label,
        coverPhoto: cover,
        photoCount: count,
      ));
    } catch (e) {
      Dbg.e('Error loading person data for label $labelId: $e');
    }
  }

  return people;

  /*
  // Hardcoded sample people data for now
  await Future.delayed(const Duration(milliseconds: 500)); // Simulate loading

  return [
    PersonData(
      id: '1',
      name: 'Person 1',
      imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&h=150&fit=crop&crop=face',
      photoCount: 25,
    ),
    PersonData(
      id: '2',
      name: 'Person 2',
      imageUrl: 'https://images.unsplash.com/photo-1494790108755-2616b612b786?w=150&h=150&fit=crop&crop=face',
      photoCount: 18,
    ),
    PersonData(
      id: '3',
      name: 'Person 3',
      // No image URL - will show initials
      photoCount: 12,
    ),
    PersonData(
      id: '4',
      name: 'Person 4',
      imageUrl: 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=150&h=150&fit=crop&crop=face',
      photoCount: 31,
    ),
    PersonData(
      id: '5',
      name: 'Person 5',
      imageUrl: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=150&h=150&fit=crop&crop=face',
      photoCount: 7,
    ),
    PersonData(
      id: '6',
      name: 'Person 6',
      imageUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150&h=150&fit=crop&crop=face',
      photoCount: 22,
    ),
    PersonData(
      id: '7',
      name: 'Person 7',
      // No image URL - will show initials
      photoCount: 9,
    ),
    PersonData(
      id: '8',
      name: 'Person 8',
      imageUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop&crop=face',
      photoCount: 15,
    ),
  ];
  */
}

String generateStoryDescription(String title, int count) {
  final List<String> templates = [
    "You ventured through the moments of {title}.",
    "Captured memories from your {title} journey.",
    "A visual journal of {title}.",
    "Your lens tells a story from {title}.",
    "Snippets of life from {title}.",
    "Moments frozen in time — {title}.",
    "Photos that whisper stories of {title}.",
    "A glimpse into your adventures in {title}.",
    "Revisiting your {title} timeline.",
    "Snapshots from your {title} days.",
  ];

  final template = (templates..shuffle()).first;
  return template
      .replaceAll('{title}', title)
      .replaceAll('{count}', count.toString());
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Story> stories = [];
  List<PersonData> people = [];
  bool isLoading = true;
  bool isPeopleLoading = true;
  AssetPathEntity? album;

  @override
  void initState() {
    super.initState();
    loadData();
    Dbg.i('hallo');
  }

  void loadData() async {
    try {
      // Load both stories and people concurrently
      final futures = await Future.wait([
        loadStoriesFromDB(),
        loadPeopleFromDB(),
      ]);

      setState(() {
        stories = futures[0] as List<Story>;
        people = futures[1] as List<PersonData>;
        isLoading = false;
        isPeopleLoading = false;
      });
    } catch (e) {
      // Handle error gracefully
      setState(() {
        isLoading = false;
        isPeopleLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    }
  }

  Widget _buildPeopleSection() {
    if (isPeopleLoading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (people.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'People',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: people.length,
            itemBuilder: (context, index) {
              final person = people[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: PersonPhotoWidget(
                  name: person.name,
                  imageUrl: person.imageUrl,
                  coverPhoto: person.coverPhoto,
                  size: 80.0,
                  photoCount: person.photoCount,
                  showPhotoCount: true,
                  isEditable: true,
                  onNameChanged: (newName) => _updatePersonName(index, newName),
                  onTap: () {
                    // Navigate to person's photos
                    _navigateToPersonPhotos(person);
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _updatePersonName(int index, String newName) async {
    if (index < 0 || index >= people.length) return;

    // Update in the backend
    await updateLabel(people[index].id, newName);

    setState(() {
      final updatedPerson = PersonData(
        id: people[index].id,
        name: newName,
        imageUrl: people[index].imageUrl,
        imagePath: people[index].imagePath,
        coverPhoto: people[index].coverPhoto,
        photoCount: people[index].photoCount,
      );
      people[index] = updatedPerson;
    });

    // Here you would typically save to database
    // await DatabaseService.updatePersonName(people[index].id, newName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated name to "$newName"'),
          backgroundColor: Colors.grey[800],
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _navigateToPersonPhotos(PersonData person) {
    // Navigate to a page showing all photos of this person
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => PersonPhotosPage(
              personId: person.id,
              personName: person.name,
              coverPhoto: person.coverPhoto,
            ),
      ),
    );
  }

  Widget _buildStoriesSection() {
    if (stories.isEmpty) {
      return const SizedBox.shrink();
    }

    return CustomScrollView(
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(), 
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Stories',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final story = stories[index];
              final cover = story.assets.first;
              final description = generateStoryDescription(
                story.title,
                story.assets.length,
              );

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewPage(storyId: story.id),
                    ),
                  );
                },
                child: Card(
                  color: Colors.black,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 3 / 2,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                          child: AssetEntityImage(
                            cover,
                            isOriginal: false,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              description,
                              maxLines: 3,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }, childCount: stories.length),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // People section
                    _buildPeopleSection(),

                    // Stories section
                    _buildStoriesSection(),

                    // Year highlights section
                    const YearHighlightsWidget(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
    );
  }
}
