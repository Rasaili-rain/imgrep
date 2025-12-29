import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class PersonPhotoWidget extends StatefulWidget {
  final String name;
  final String? imageUrl;
  final String? imagePath;
  final AssetEntity? coverPhoto;
  final double size;
  final VoidCallback? onTap;
  final bool showLabel;
  final bool showPhotoCount;
  final int photoCount;
  final TextStyle? nameStyle;
  final Color? backgroundColor;
  final Function(String)? onNameChanged;
  final bool isEditable;

  const PersonPhotoWidget({
    Key? key,
    required this.name,
    this.imageUrl,
    this.imagePath,
    this.coverPhoto,
    this.size = 80.0,
    this.onTap,
    this.showLabel = true,
    this.showPhotoCount = false,
    this.photoCount = 0,
    this.nameStyle,
    this.backgroundColor,
    this.onNameChanged,
    this.isEditable = true,
  }) : super(key: key);

  @override
  State<PersonPhotoWidget> createState() => _PersonPhotoWidgetState();
}

class _PersonPhotoWidgetState extends State<PersonPhotoWidget> {
  late TextEditingController _nameController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (!widget.isEditable) return;
    setState(() {
      _isEditing = true;
    });
  }

  void _finishEditing() {
    setState(() {
      _isEditing = false;
    });
    if (widget.onNameChanged != null && _nameController.text.trim().isNotEmpty) {
      widget.onNameChanged!(_nameController.text.trim());
    }
  }

  void _showEditDialog() {
    if (!widget.isEditable) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Edit Name',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: _nameController,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter person name',
              hintStyle: TextStyle(color: Colors.grey[500]),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            onSubmitted: (_) {
              Navigator.of(context).pop();
              _finishEditing();
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                _nameController.text = widget.name; // Reset to original
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _finishEditing();
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.backgroundColor ?? Colors.grey.shade800,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _buildImage(),
                ),
              ),
              if (widget.showPhotoCount && widget.photoCount > 0)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: Text(
                      widget.photoCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              if (widget.isEditable)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _showEditDialog,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.showLabel) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onLongPress: widget.isEditable ? _showEditDialog : null,
              child: SizedBox(
                width: widget.size + 20,
                child: Text(
                  _nameController.text.isNotEmpty ? _nameController.text : widget.name,
                  textAlign: TextAlign.center,
                  style: widget.nameStyle ??
                      TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (widget.coverPhoto != null) {
      return AssetEntityImage(
        widget.coverPhoto!,
        fit: BoxFit.cover,
        isOriginal: false,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAvatar();
        },
      );
    } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
      return Image.network(
        widget.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAvatar();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.blue.shade300,
              ),
            ),
          );
        },
      );
    } else if (widget.imagePath != null && widget.imagePath!.isNotEmpty) {
      return Image.asset(
        widget.imagePath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAvatar();
        },
      );
    } else {
      return _buildFallbackAvatar();
    }
  }

  Widget _buildFallbackAvatar() {
    final displayName = _nameController.text.isNotEmpty ? _nameController.text : widget.name;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            _getColorFromName(displayName).withOpacity(0.7),
            _getColorFromName(displayName),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _getInitials(displayName),
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * 0.3,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    List<String> nameParts = name.trim().split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0][0].toUpperCase();
    }
    return '?';
  }

  Color _getColorFromName(String name) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.pink,
      Colors.deepOrange,
      Colors.lightGreen,
    ];

    int hash = name.hashCode;
    return colors[hash.abs() % colors.length];
  }
}
