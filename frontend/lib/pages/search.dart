import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:imgrep/utils/debug_logger.dart';
import 'package:imgrep/services/api/upload_image.dart';
import 'package:imgrep/services/database_service.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:imgrep/widgets/search_image_viewer.dart';
import 'package:imgrep/services/api/user.dart';

// Import the search-specific image viewer
// You'll need to create this file: widgets/search_image_viewer.dart

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  File? _selectedImage;
  final TextEditingController _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _imgIds = [];


  //
  //  Text Based Search Functions
  //

  Future<void> _textSearch() async {
    String query = _textController.text;
    if (query.trim().isEmpty) {
      return;
    }
    Map<String, dynamic>? res = await searchImage(query, 10);
    if (res == null) return;

    final indices = res["indices"];
    List<String> ids = [];

    for (int idx in indices) {
      String? id = await DatabaseService.getIdFromFaissIndex(idx.toString());
      if (id != null) {
        ids.add(id);
      }
    }

    Dbg.i(indices);
    Dbg.i(ids);

    setState(() {
      _imgIds.clear();
      _imgIds.addAll(ids);
      _textController.clear();
    });
  }


  //
  // Image Based Search
  //

  Future<void> _imageSearch() async {
    if (_selectedImage == null) return;
    final userId = await UserManager.getUserId();
    if (userId == null) {
      Dbg.e("User ID is null. Create a new user please.");
      return;
    }
    Map<String, dynamic>? res = await imageToImageSearch(_selectedImage!.path, userId);
    if (res == null) {
      Dbg.e("Response was null");
      return;
    }

    final indices = res["indices"];
    List<String> ids = [];

    for (int idx in indices) {
      String? id = await DatabaseService.getIdFromFaissIndex(idx.toString());
      if (id != null) {
        ids.add(id);
      }
    }

    Dbg.i(indices);
    Dbg.i(ids);

    setState(() {
      _imgIds.clear();
      _imgIds.addAll(ids);
      _textController.clear();
    });
  }

  // Combined both search
  Future<void> _search() async {
    await _textSearch();
    await _imageSearch();
  }

  // Image picker for choosing the search image
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _textController.clear();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: GridView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(4),
          itemCount: _imgIds.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            String id = _imgIds[index];

            // Use FutureBuilder to load thumbnail asynchronously
            return FutureBuilder<Uint8List?>(
              future: ImageService.getThumbnailById(id),
              builder: (context, snapshot) {
                Widget content;

                if (snapshot.connectionState == ConnectionState.waiting) {
                  content = const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                } else if (snapshot.hasError || snapshot.data == null) {
                  content = const Icon(
                    Icons.error_outline,
                    color: Colors.grey,
                    size: 32,
                  );
                } else {
                  content = Image.memory(snapshot.data!, fit: BoxFit.cover);
                }

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SearchImageViewerWidget(
                          initialIndex: index, // This is now the correct index within search results
                          imageIds: _imgIds, // Pass the list of search result IDs
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: content,
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Container(
        margin: EdgeInsets.only(left: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 20),
            Container(
              height: 65,
              width: 60,
              decoration: BoxDecoration(
                color: Color(0xFF2B2D30),
                borderRadius: BorderRadius.circular(15),
              ),
              child: IconButton(
                 onPressed: _pickImage,
                  icon: Icon(Icons.image, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
              ),
            ),

            SizedBox(width: 12),

            Expanded(
              child: SizedBox(
                height: 65,
                child: TextField(
                  controller: _textController,
                  readOnly: _selectedImage != null,
                  showCursor: _selectedImage == null,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Color(0xFF2B2D30),
                    hintText:
                        _selectedImage == null
                            ? 'What are we looking up for today'
                            : null,
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 12),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 22,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),

                    prefixIcon:
                        _selectedImage != null
                            ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        _selectedImage!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedImage = null;
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.7,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : null,

                    suffixIcon: Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _search,
                            icon: SvgPicture.asset('assets/icons/SendIcon.svg'),
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}
