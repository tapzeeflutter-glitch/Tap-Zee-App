import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserMarkerWidget extends StatelessWidget {
  final String? photoURL;
  final String displayName;
  final bool isOnline;
  final double size;

  const UserMarkerWidget({
    Key? key,
    this.photoURL,
    required this.displayName,
    this.isOnline = true,
    this.size = 40.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isOnline ? Colors.green : Colors.grey,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: photoURL != null && photoURL!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoURL!,
                width: size - 6, // Account for border
                height: size - 6,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey.shade300,
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.grey.shade600,
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade300,
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.grey.shade600,
                  ),
                ),
              )
            : Container(
                color: Colors.blue.shade400,
                child: Center(
                  child: Text(
                    _getInitials(displayName),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    List<String> nameParts = name.split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0][0].toUpperCase();
    }
    return '?';
  }
}

class CurrentUserMarkerWidget extends StatelessWidget {
  final String? photoURL;
  final String displayName;
  final double size;

  const CurrentUserMarkerWidget({
    Key? key,
    this.photoURL,
    required this.displayName,
    this.size = 45.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.blue, width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: photoURL != null && photoURL!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoURL!,
                width: size - 8, // Account for border
                height: size - 8,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.blue.shade300,
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.white,
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.blue.shade300,
                  child: Icon(
                    Icons.person,
                    size: size * 0.6,
                    color: Colors.white,
                  ),
                ),
              )
            : Container(
                color: Colors.blue.shade500,
                child: Center(
                  child: Text(
                    _getInitials(displayName),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';

    List<String> nameParts = name.split(' ');
    if (nameParts.length >= 2) {
      return '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
    } else if (nameParts.isNotEmpty) {
      return nameParts[0][0].toUpperCase();
    }
    return '?';
  }
}
