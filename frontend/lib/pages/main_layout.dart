import 'package:flutter/material.dart';
import 'package:imgrep/widgets/nav_bar.dart';
import 'package:imgrep/widgets/app_bar.dart';

// Pages
import 'package:imgrep/pages/home.dart';
import 'package:imgrep/pages/search.dart';
import 'package:imgrep/pages/library.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  MainLayoutState createState() => MainLayoutState();
}

class MainLayoutState extends State<MainLayout> {
  // Note(slok): PageControllers and Page Index are here temporarily
  // Maybe shift to some provider shit when needed
  final PageController _pageController = PageController();
  int _currentPageIndex = 0;

  void _onNavBarClick(int index) {
    setState(() {
      _currentPageIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ImGrepAppBar(),
      backgroundColor: Colors.black,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPageIndex = index;
          });
        },
        children: [
          HomeScreen(),
          SearchScreen(),
          LibraryScreen(),
        ],
      ),
      bottomNavigationBar: ImGrepNavBar(
        onClick: _onNavBarClick,
        pageIndex: _currentPageIndex,
      ),
    );
  }
}
