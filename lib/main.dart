import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Get available cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);

  runApp(ProfessionalVideoApp(camera: firstCamera, cameras: cameras));
}

class ProfessionalVideoApp extends StatelessWidget {
  final CameraDescription camera;
  final List<CameraDescription> cameras;

  const ProfessionalVideoApp({Key? key, required this.camera, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Professional Video Filmer', theme: ThemeData.dark(), home: ProfessionalVideoRecorder(camera: camera, cameras: cameras));
  }
}

class ProfessionalVideoRecorder extends StatefulWidget {
  final CameraDescription camera;
  final List<CameraDescription> cameras;

  const ProfessionalVideoRecorder({Key? key, required this.camera, required this.cameras}) : super(key: key);

  @override
  _ProfessionalVideoRecorderState createState() => _ProfessionalVideoRecorderState();
}

class _ProfessionalVideoRecorderState extends State<ProfessionalVideoRecorder> with WidgetsBindingObserver {
  // Camera variables
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  bool _isRecording = false;
  bool _isFrontCamera = false;
  FlashMode _flashMode = FlashMode.off;
  late CameraDescription _currentCamera;
  List<File> _videoGallery = [];
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  ResolutionPreset _resolutionPreset = ResolutionPreset.veryHigh;

  // Bluetooth variables
  final FlutterBluePlus _flutterBlue = FlutterBluePlus();
  List<BluetoothDevice> _bluetoothDevices = [];
  List<BluetoothDevice> _connectedDevices = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // UI state variables
  int _currentTabIndex = 0;
  bool _showSettings = false;
  double _zoomLevel = 1.0;
  double _exposureOffset = 0.0;
  bool _showGrid = true;
  bool _showAudioLevels = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentCamera = widget.camera;
    _initializeCamera();
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController.dispose();
    _scanSubscription?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController != null) {
        _initializeCamera();
      }
    }
  }

  void _initializeCamera() {
    _cameraController = CameraController(_currentCamera, _resolutionPreset, enableAudio: true);

    _initializeControllerFuture = _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _cameraController.setFlashMode(_flashMode);
    });
  }

  Future<void> _checkPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.locationWhenInUse.request();
  }

  // Camera control methods
  Future<void> _startRecording() async {
    try {
      await _initializeControllerFuture;
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, 'professional_video_${DateTime.now().millisecondsSinceEpoch}.mp4');

      await _cameraController.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Start recording timer
      _recordingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration += Duration(seconds: 1);
        });
      });
    } catch (e) {
      print("Error starting video recording: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _cameraController.stopVideoRecording().then((xFile) async {
        final directory = await getApplicationDocumentsDirectory();
        final path = join(directory.path, 'professional_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
        xFile.saveTo(path);

        setState(() {
          _isRecording = false;
          _recordingTimer?.cancel();
        });

        // Refresh gallery
        _loadVideoGallery();
      });
    } catch (e) {
      print("Error stopping video recording: $e");
    }
  }

  Future<void> _loadVideoGallery() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync().where((file) => file.path.endsWith('.mp4')).map((file) => File(file.path)).toList();

    setState(() {
      _videoGallery = files.reversed.toList();
    });
  }

  void _toggleCamera() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _currentCamera = widget.cameras.firstWhere((camera) => camera.lensDirection == (_isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back), orElse: () => widget.cameras.first);
      _initializeCamera();
    });
  }

  void _toggleFlash() {
    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      _cameraController.setFlashMode(_flashMode);
    });
  }

  void _changeResolution(ResolutionPreset preset) {
    setState(() {
      _resolutionPreset = preset;
      _initializeCamera();
    });
  }

  // Bluetooth methods
  void _startBluetoothScan() {
    if (_isScanning) return;

    setState(() {
      _bluetoothDevices.clear();
      _isScanning = true;
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (ScanResult result in results) {
          if (!_bluetoothDevices.any((device) => device.id == result.device.id)) {
            _bluetoothDevices.add(result.device);
          }
        }
      });
    });

    FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    // Stop scanning after 10 seconds
    Future.delayed(Duration(seconds: 10), () {
      _stopBluetoothScan();
    });
  }

  void _stopBluetoothScan() {
    if (!_isScanning) return;

    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();

    setState(() {
      _isScanning = false;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        _connectedDevices.add(device);
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected to ${device.name}')));
    } catch (e) {
      print("Error connecting to device: $e");
    }
  }

  void _disconnectDevice(BluetoothDevice device) async {
    try {
      await device.disconnect();
      setState(() {
        _connectedDevices.remove(device);
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Disconnected from ${device.name}')));
    } catch (e) {
      print("Error disconnecting from device: $e");
    }
  }

  // UI components
  Widget _buildCameraTab() {
    return Stack(
      children: [
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Stack(
                children: [
                  CameraPreview(_cameraController),

                  // Grid overlay
                  if (_showGrid) _buildGridOverlay(),

                  // Audio levels
                  if (_showAudioLevels && _isRecording) _buildAudioLevels(),

                  // Recording timer
                  if (_isRecording) _buildRecordingTimer(),

                  // Connected devices indicator
                  if (_connectedDevices.isNotEmpty) _buildConnectedDevicesIndicator(),
                ],
              );
            } else {
              return Center(child: CircularProgressIndicator());
            }
          },
        ),

        // Top controls
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: Icon(Icons.settings), onPressed: () => setState(() => _showSettings = !_showSettings)),

              // Resolution indicator
              Text(_getResolutionLabel(), style: TextStyle(backgroundColor: Colors.black54, fontSize: 16, fontWeight: FontWeight.bold)),

              IconButton(icon: Icon(Icons.bluetooth), onPressed: () => setState(() => _currentTabIndex = 1)),
            ],
          ),
        ),

        // Settings panel
        if (_showSettings) _buildSettingsPanel(),

        // Bottom controls
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Column(
            children: [
              // Recording button
              GestureDetector(
                onTap: _isRecording ? _stopRecording : _startRecording,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.red, border: Border.all(color: Colors.white, width: 3)),
                  child: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, color: Colors.white, size: 40),
                ),
              ),

              SizedBox(height: 20),

              // Secondary controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(icon: Icon(Icons.cameraswitch, color: Colors.white), onPressed: _toggleCamera),

                  IconButton(icon: Icon(_flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off, color: Colors.white), onPressed: _toggleFlash),

                  IconButton(icon: Icon(Icons.video_library, color: Colors.white), onPressed: () => setState(() => _currentTabIndex = 2)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothTab() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Devices'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => setState(() => _currentTabIndex = 0)),
      ),
      body: Column(
        children: [
          // Scan button
          Container(
            padding: EdgeInsets.all(16),
            child: Row(children: [Expanded(child: ElevatedButton(onPressed: _isScanning ? _stopBluetoothScan : _startBluetoothScan, child: Text(_isScanning ? 'Stop Scan' : 'Scan for Devices')))]),
          ),

          // Status
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.bluetooth, color: _isScanning ? Colors.blue : Colors.grey),
                SizedBox(width: 8),
                Text(_isScanning ? 'Scanning...' : 'Not Scanning', style: TextStyle(color: _isScanning ? Colors.blue : Colors.grey)),
                Spacer(),
                Text('Found: ${_bluetoothDevices.length} devices'),
              ],
            ),
          ),

          Divider(),

          // Connected devices
          if (_connectedDevices.isNotEmpty) ...[
            Padding(padding: EdgeInsets.all(16), child: Text('Connected Devices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: _connectedDevices.length,
                itemBuilder: (context, index) {
                  final device = _connectedDevices[index];
                  return ListTile(
                    leading: Icon(Icons.bluetooth_connected),
                    title: Text(device.name.isEmpty ? 'Unknown Device' : device.name),
                    subtitle: Text(device.id.toString()),
                    trailing: IconButton(icon: Icon(Icons.link_off), onPressed: () => _disconnectDevice(device)),
                  );
                },
              ),
            ),
          ],

          // Available devices
          Padding(padding: EdgeInsets.all(16), child: Text('Available Devices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          Expanded(
            flex: 2,
            child:
                _bluetoothDevices.isEmpty
                    ? Center(child: Text('No devices found. Start scanning to discover devices.', textAlign: TextAlign.center))
                    : ListView.builder(
                      itemCount: _bluetoothDevices.length,
                      itemBuilder: (context, index) {
                        final device = _bluetoothDevices[index];
                        final isConnected = _connectedDevices.any((d) => d.id == device.id);

                        return ListTile(
                          leading: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
                          title: Text(device.name.isEmpty ? 'Unknown Device' : device.name),
                          subtitle: Text(device.id.toString()),
                          trailing: isConnected ? Text('Connected', style: TextStyle(color: Colors.green)) : ElevatedButton(onPressed: () => _connectToDevice(device), child: Text('Connect')),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryTab() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Video Gallery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => setState(() => _currentTabIndex = 0)),
      ),
      body:
          _videoGallery.isEmpty
              ? Center(child: Text('No videos recorded yet.'))
              : GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 4),
                itemCount: _videoGallery.length,
                itemBuilder: (context, index) {
                  final videoFile = _videoGallery[index];
                  return GestureDetector(
                    onTap: () {
                      // Play video
                      showDialog(context: context, builder: (context) => Dialog(child: VideoPlayerWidget(videoFile: videoFile)));
                    },
                    child: Stack(
                      children: [
                        // Thumbnail would be better here, but for simplicity using icon
                        Container(color: Colors.black, child: Icon(Icons.videocam, size: 50, color: Colors.white)),
                        Positioned(bottom: 4, right: 4, child: Text('${index + 1}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildGridOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.white30)),
        child: Column(
          children: List.generate(
            2,
            (index) => Expanded(child: Row(children: List.generate(2, (index) => Expanded(child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.white30))))))),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioLevels() {
    // Simulated audio levels - in a real app you would use actual audio data
    return Positioned(
      right: 10,
      top: MediaQuery.of(context).size.height / 2 - 50,
      child: Container(
        width: 20,
        height: 100,
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: 70, // This would change based on audio input
              decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingTimer() {
    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
          child: Text(_formatDuration(_recordingDuration), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesIndicator() {
    return Positioned(
      top: 80,
      right: 16,
      child: Row(
        children: [
          Icon(Icons.bluetooth_connected, color: Colors.blue, size: 16),
          SizedBox(width: 4),
          Text('${_connectedDevices.length} connected', style: TextStyle(color: Colors.blue, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Positioned(
      top: 80,
      left: 16,
      child: Container(
        width: 200,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            Divider(),

            Text('Resolution:'),
            DropdownButton<ResolutionPreset>(
              value: _resolutionPreset,
              onChanged: (newValue) {
                if (newValue != null) {
                  _changeResolution(newValue);
                }
              },
              items: [
                DropdownMenuItem(value: ResolutionPreset.low, child: Text('Low (360p)')),
                DropdownMenuItem(value: ResolutionPreset.medium, child: Text('Medium (720p)')),
                DropdownMenuItem(value: ResolutionPreset.high, child: Text('High (1080p)')),
                DropdownMenuItem(value: ResolutionPreset.veryHigh, child: Text('Very High (4K)')),
              ],
            ),

            SizedBox(height: 10),

            Row(children: [Text('Show Grid:'), Switch(value: _showGrid, onChanged: (value) => setState(() => _showGrid = value))]),

            Row(children: [Text('Audio Levels:'), Switch(value: _showAudioLevels, onChanged: (value) => setState(() => _showAudioLevels = value))]),
          ],
        ),
      ),
    );
  }

  String _getResolutionLabel() {
    switch (_resolutionPreset) {
      case ResolutionPreset.low:
        return '360p';
      case ResolutionPreset.medium:
        return '720p';
      case ResolutionPreset.high:
        return '1080p';
      case ResolutionPreset.veryHigh:
        return '4K';
      default:
        return 'Unknown';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: IndexedStack(index: _currentTabIndex, children: [_buildCameraTab(), _buildBluetoothTab(), _buildGalleryTab()]));
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final File videoFile;

  const VideoPlayerWidget({Key? key, required this.videoFile}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(aspectRatio: _controller.value.aspectRatio, child: VideoPlayer(_controller)),

        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isPlaying ? _controller.pause() : _controller.play();
                      _isPlaying = !_isPlaying;
                    });
                  },
                ),

                IconButton(
                  icon: Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: () {
                    // Implement fullscreen functionality
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
