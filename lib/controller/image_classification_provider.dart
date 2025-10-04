import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_classification_litert/service/image_classification_service.dart';

class ImageClassificationViewmodel extends ChangeNotifier {
  final ImageClassificationService _service;
  final ImagePicker _picker = ImagePicker();

  File? _selectedImage;
  Map<String, num> _classifications = {};

  ImageClassificationViewmodel(this._service) {
    _service.initHelper();
  }

  File? get selectedImage => _selectedImage;

  Map<String, num> get classifications => Map.fromEntries(
        (_classifications.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(3),
      );

  /// Ambil gambar dari galeri
  Future<void> pickImageFromGallery() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _selectedImage = File(pickedFile.path);
      await _runClassificationOnImageFile();
    }
  }

  /// Ambil gambar dari kamera
  Future<void> takePictureWithCamera() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      _selectedImage = File(pickedFile.path);
      await _runClassificationOnImageFile();
    }
  }

  /// Jalankan klasifikasi pada gambar yang diambil
  Future<void> _runClassificationOnImageFile() async {
    if (_selectedImage == null) return;
    _classifications =
        await _service.inferenceImageFile(_selectedImage!); // Pastikan method ini ada di ImageClassificationService
    notifyListeners();
  }

  /// Jalankan klasifikasi pada kamera stream (live)
  Future<void> runClassification(CameraImage camera) async {
    _classifications = await _service.inferenceCameraFrame(camera);
    notifyListeners();
  }

  void clearImage() {
    _selectedImage = null;
    _classifications = {};
    notifyListeners();
  }

  Future<void> close() async {
    await _service.close();
  }
}
