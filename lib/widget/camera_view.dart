import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:image_classification_litert/controller/image_classification_provider.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraView extends StatefulWidget {
  final Function(CameraImage cameraImage)? onImage;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;

  const CameraView({
    super.key,
    this.onImage,
    this.onCameraLensDirectionChanged,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  bool _isCameraInitialized = false;

  List<CameraDescription> _cameras = [];

  CameraController? controller;
  XFile? _selectedImage;
  bool _isProcessing = false;

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    final previousCameraController = controller;
    final cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );
    await previousCameraController?.dispose();

    cameraController
        .initialize()
        .then((value) {
          if (mounted) {
            setState(() {
              controller = cameraController;
              if (widget.onImage != null) {
                controller!.startImageStream(_processCameraImage);
              }
              if (widget.onCameraLensDirectionChanged != null) {
                widget.onCameraLensDirectionChanged!(
                  cameraDescription.lensDirection,
                );
              }
              _isCameraInitialized = controller!.value.isInitialized;
            });
          }
        })
        .catchError((e) {
          print('Error initializing camera: $e');
        });
  }

  void initCamera() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    await onNewCameraSelected(_cameras.first);
  }

  //function to take image and choose from gallery
  Future<void> _takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return;

    final image = await controller!.takePicture();
    setState(() {
      _selectedImage = image;
    });

    //send to provider for clarification
    final provider = Provider.of<ImageClassificationViewmodel>(
      context,
      listen: false,
    );
    await provider.classifyImage(File(image.path));
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = pickedFile;
      });

      final provider = Provider.of<ImageClassificationViewmodel>(
        context,
        listen: false,
      );
      await provider.classifyImage(File(pickedFile.path));
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing) {
      return;
    }

    _isProcessing = true;
    if (widget.onImage != null) {
      await widget.onImage!(image);
    }
    _isProcessing = false;
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);

    initCamera();

    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    controller!
      ..stopImageStream()
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController != null || !cameraController!.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.inactive:
        cameraController.dispose();
        break;
      case AppLifecycleState.resumed:
        onNewCameraSelected(cameraController.description);
        break;
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ImageClassificationViewmodel>(context);
    return Scaffold(
      appBar: AppBar(title: Text("Image Classification")),

      body: Column(
        children: [
          Expanded(
            child: _selectedImage != null
                ? Image.file(File(_selectedImage!.path))
                : _isCameraInitialized
                ? CameraPreview(controller!)
                : const Center(child: CircularProgressIndicator()),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _takePicture,
                  icon: Icon(Icons.camera_alt),
                  label: Text("Camera"),
                ),
                ElevatedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: Icon(Icons.photo_library),
                  label: Text("Gallery"),
                ),
              ],
            ),
          ),
          if (provider.classifications.isNotEmpty)
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                children: provider.classifications.entries.map((e) {
                  return Text(
                    "${e.key}: ${(e.value * 100).toStringAsFixed(2)}%",
                    style: TextStyle(fontSize: 16),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}