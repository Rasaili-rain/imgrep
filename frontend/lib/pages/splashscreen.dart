import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:imgrep/services/image_service.dart';
import 'package:imgrep/pages/main_layout.dart';
import 'package:imgrep/utils/settings.dart';

class SplashScreen extends StatefulWidget {
  final bool syncDatabase;
  const SplashScreen({super.key, this.syncDatabase = false});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    ImageService.incrementalSync();
    ImageService.syncProgressNotifier.addListener(() {
      setState(() {
        _progress = ImageService.syncProgressNotifier.value;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadImagesAndNavigate();
    });
  }

  Future<void> _loadImagesAndNavigate() async {
    // Syncing the database with gallery images
    if (widget.syncDatabase) {
      await ImageService.syncGalleryImages();
    }

    // Loading initial images
    await ImageService.loadMoreImages(amount: Settings.initialPageSize);

    // Loading more images in the background
    ImageService.loadMoreImages();

    if (!mounted) return;

    // Switching to the main pages
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return MainLayout();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Lottie.asset(
              'assets/icons/logosplash.json',
              height: 600,
              width: 700,
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                spacing: 0,
                children: [
                  // Rendering progress bar if we're syncing the database
                  if (widget.syncDatabase) ...[
                    Text(
                      'Syncing the database',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade300,
                      color: Colors.blue,
                    ),
                  ],

                  Text(
                    'ImGrep',
                    style: TextStyle(color: Colors.white, fontSize: 33),
                  ),
                  Text(
                    'Powered By Lobic',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w100,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
