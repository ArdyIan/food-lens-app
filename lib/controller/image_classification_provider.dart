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
  bool _isModelReady = false; // flag optional

  ImageClassificationViewmodel(this._service) {
    _init();
  }

  // PUBLIC GETTERS
  File? get selectedImage => _selectedImage;
  bool get isModelReady => _isModelReady;

  Map<String, num> get classifications => Map.fromEntries(
    (_classifications.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3),
  );

  // Inisialisasi model secara asinkron
  Future<void> _init() async {
    try {
      await _service.loadModel(); // <-- sesuaikan dengan nama method di service
      _isModelReady = true;
      notifyListeners();
    } catch (e) {
      // logging optional
      _isModelReady = false;
      notifyListeners();
    }
  }

  /// Ambil gambar dari galeri
  Future<void> pickImageFromGallery() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _selectedImage = File(pickedFile.path);
      notifyListeners();
      await classifyImage(_selectedImage!);
    }
  }

  /// Ambil gambar dari kamera
  Future<void> takePictureWithCamera() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      _selectedImage = File(pickedFile.path);
      notifyListeners();
      await classifyImage(_selectedImage!);
    }
  }

  /// Method utama untuk menjalankan klasifikasi gambar (dipanggil UI)
  Future<void> classifyImage(File imageFile) async {
    // Pastikan model siap (service.classify juga bisa memanggil loadModel jika perlu)
    if (!_isModelReady) {
      await _service.loadModel();
      _isModelReady = true;
      notifyListeners();
    }

    final result = await _service.classify(imageFile);
    // convert Map<String,double> ke Map<String,num> jika perlu
    _classifications = result.map((k, v) => MapEntry(k, v));
    notifyListeners();
  }

  /// Jalankan klasifikasi pada frame kamera (opsional)
  Future<void> runClassification(CameraImage camera) async {
    final result = await _service.inferenceCameraFrame(camera);
    _classifications = result.map((k, v) => MapEntry(k, v));
    notifyListeners();
  }

  /// Hapus gambar dan hasil klasifikasi
  void clearImage() {
    _selectedImage = null;
    _classifications = {};
    notifyListeners();
  }

  /// Tutup service
  Future<void> close() async {
    await _service.close();
  }
}
