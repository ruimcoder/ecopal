import 'package:flutter/material.dart';

/// Main Fish Scanner screen.
/// Hosts the camera preview and overlay stack.
/// Camera integration added in Issue #10.
class FishScannerScreen extends StatelessWidget {
  const FishScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ecopal',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // Settings screen — future issue
            },
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text(
              'Camera coming soon',
              style: TextStyle(color: Colors.white54),
            ),
            SizedBox(height: 8),
            Text(
              'Point at a fish counter to identify species',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
