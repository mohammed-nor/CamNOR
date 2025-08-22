import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );
  
  runApp(MaterialApp(
    theme: ThemeData.dark(),
    home: CameraApp(camera: firstCamera, cameras: cameras),
  ));
}

class CameraApp extends StatefulWidget {
  final CameraDescription camera;
  final List<CameraDescription> cameras;
  
  const CameraApp({Key? key, required this.camera, required this.cameras}) : super(key: key);

  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> with WidgetsBindingObserver {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isRecording = false;
  bool _isFrontCamera = false;
  FlashMode _flashMode = FlashMode.off;
  late CameraDescription _currentCamera;
  List<File> _galleryItems = [];
  int _currentMode = 0; // 0 = photo, 1 = video
  VideoPlayerController? _videoController;
  bool _isGalleryVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentCamera = widget.camera;
    _initializeCamera();
    _loadGallery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null) {
        _initializeCamera();
      }
    }
  }

  void _initializeCamera() {
    _controller = CameraController(
      _currentCamera,
      ResolutionPreset.high,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.setFlashMode(_flashMode);
    });
  }

  Future<void> _loadGallery() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync().where((file) => 
      file.path.endsWith('.jpg') || file.path.endsWith('.mp4')
    ).map((file) => File(file.path)).toList();
    
    setState(() {
      _galleryItems = files.reversed.toList();
    });
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      await _controller.takePicture().then((xFile) {
        xFile.saveTo(path);
        _loadGallery(); // Refresh gallery
      });
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  Future<void> _startVideoRecording() async {
    try {
      await _initializeControllerFuture;
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.mp4');
      
      await _controller.startVideoRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      print("Error starting video recording: $e");
    }
  }

  Future<void> _stopVideoRecording() async {
    try {
      await _controller.stopVideoRecording().then((xFile) async {
        final directory = await getApplicationDocumentsDirectory();
        final path = join(directory.path, '${DateTime.now().millisecondsSinceEpoch}.mp4');
        xFile.saveTo(path);
        setState(() => _isRecording = false);
        _loadGallery(); // Refresh gallery
      });
    } catch (e) {
      print("Error stopping video recording: $e");
    }
  }

  void _toggleCamera() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _currentCamera = widget.cameras.firstWhere(
        (camera) => camera.lensDirection == 
          (_isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => widget.cameras.first,
      );
      _initializeCamera();
    });
  }

  void _toggleFlash() {
    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      _controller.setFlashMode(_flashMode);
    });
  }

  void _toggleMode() {
    setState(() {
      _currentMode = _currentMode == 0 ? 1 : 0;
    });
  }

  void _toggleGallery() {
    setState(() {
      _isGalleryVisible = !_isGalleryVisible;
    });
  }

  Widget _buildGallery() {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _galleryItems.length,
      itemBuilder: (context, index) {
        final file = _galleryItems[index];
        final isVideo = file.path.endsWith('.mp4');
        
        return GestureDetector(
          onTap: () {
            if (isVideo) {
              _videoController = VideoPlayerController.file(file)
                ..initialize().then((_) {
                  setState(() {});
                  _videoController!.play();
                });
              
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: _videoController != null && _videoController!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      )
                    : Container(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                ),
              );
            } else {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: Image.file(file),
                ),
              );
            }
          },
          child: isVideo
            ? Stack(
                children: [
                  Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey,
                      child: Icon(Icons.videocam, color: Colors.white),
                    ),
                  ),
                  Positioned.fill(
                    child: Icon(Icons.play_circle_fill, color: Colors.white.withOpacity(0.7)),
                  ),
                ],
              )
            : Image.file(file, fit: BoxFit.cover),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isGalleryVisible
          ? _buildGallery()
          : FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Stack(
                    children: [
                      CameraPreview(_controller),
                      Positioned(
                        top: 40,
                        left: 16,
                        right: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(Icons.photo_library),
                              onPressed: _toggleGallery,
                            ),
                            IconButton(
                              icon: Icon(_flashMode == FlashMode.torch 
                                ? Icons.flash_on 
                                : Icons.flash_off),
                              onPressed: _toggleFlash,
                            ),
                            IconButton(
                              icon: Icon(Icons.cameraswitch),
                              onPressed: _toggleCamera,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _toggleMode,
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _currentMode == 0 ? 'PHOTO' : 'VIDEO',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            SizedBox(width: 20),
                            GestureDetector(
                              onLongPress: _currentMode == 1 ? _startVideoRecording : null,
                              onLongPressUp: _currentMode == 1 && _isRecording ? _stopVideoRecording : null,
                              onTap: _currentMode == 0 ? _takePicture : null,
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(color: Colors.black, width: 3),
                                ),
                                child: _isRecording
                                    ? Icon(Icons.stop, color: Colors.red, size: 40)
                                    : Icon(
                                        _currentMode == 0 ? Icons.camera : Icons.videocam,
                                        color: Colors.black,
                                        size: 40,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                } else {
                  return Center(child: CircularProgressIndicator());
                }
              },
            ),
    );
  }
}