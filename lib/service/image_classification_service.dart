import 'dart:developer';
import 'dart:io';
import 'dart:math' as math; // Import math untuk fungsi exp()
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'isolate_inference.dart'; // Asumsikan ini adalah file custom Anda
import 'dart:isolate';

class ImageClassificationService {
  // Path Model dan Label
  final String _modelPath = 'assets/food_model.tflite';
  final String _labelsPath = 'assets/labels.txt';

  // Variabel utama
  Interpreter? _interpreter;
  List<String> _labels = [];
  late Tensor inputTensor;
  late Tensor outputTensor;
  late final IsolateInference isolateInference;

  // --- FUNGSI TAMBAHAN: SOFTMAX ---
  /// Menghitung fungsi Softmax pada logits (skor mentah) untuk mendapatkan probabilitas.
  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];

    // 1. Hitung eksponensial (e^score)
    final exp = logits.map((e) => math.exp(e)).toList();

    // 2. Hitung jumlah semua eksponensial
    final sumExp = exp.reduce((a, b) => a + b);

    // 3. Bagi setiap eksponensial dengan total sum
    if (sumExp == 0) return logits.map((_) => 0.0).toList();

    // Hasilnya adalah probabilitas, totalnya ~1.0
    return exp.map((e) => e / sumExp).toList();
  }
  // ---------------------------------

  // Load Model
  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions()
        ..useNnApiForAndroid = true
        ..useMetalDelegateForIOS = true;

      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      inputTensor = _interpreter!.getInputTensors().first;
      outputTensor = _interpreter!.getOutputTensors().first;

      log(' Model berhasil dimuat dari $_modelPath');
    } catch (e) {
      log('Gagal memuat model: $e');
    }
  }

  // Load Labels
  Future<void> _loadLabels() async {
    try {
      final labelTxt = await rootBundle.loadString(_labelsPath);
      _labels = labelTxt.split('\n');
      // Hapus baris kosong yang mungkin ada di akhir file
      _labels.removeWhere((label) => label.trim().isEmpty);
      log(' Label berhasil dimuat (${_labels.length} label)');
    } catch (e) {
      log(' Gagal memuat label: $e');
    }
  }

  // Fungsi untuk load model & label sekaligus
  Future<void> loadModel() async {
    await _loadLabels();
    await _loadModel();

    isolateInference = IsolateInference();
    await isolateInference.start();

    log(' Model dan label siap digunakan untuk inferensi');
  }

  // Inferensi Kamera (Opsional, tidak diubah)
  Future<Map<String, double>> inferenceCameraFrame(
    CameraImage cameraImage,
  ) async {
    try {
      if (_interpreter == null) await loadModel();

      var isolateModel = InferenceModel(
        cameraImage,
        _interpreter!.address,
        _labels,
        inputTensor.shape,
        outputTensor.shape,
      );

      ReceivePort responsePort = ReceivePort();
      isolateInference.sendPort.send(
        isolateModel..responsePort = responsePort.sendPort,
      );

      var results = await responsePort.first;
      return results;
    } catch (e) {
      log(' Error inferenceCameraFrame: $e');
      return {};
    }
  }

  // Inferensi dari File Gambar (DIPERBAIKI)
  Future<Map<String, double>> inferenceImageFile(File imageFile) async {
    try {
      if (_interpreter == null) await loadModel();

      log('🧩 Input tensor type: ${inputTensor.type}');

      final imageData = File(imageFile.path).readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) throw Exception('Gagal membaca gambar');

      // Resize ke 224x224 (sesuai input model)
      final resizedImage = img.copyResize(image, width: 224, height: 224);

      // Ubah piksel ke integer 0–255 (bukan float), karena model input uint8
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(224, (x) {
            final pixel = resizedImage.getPixel(x, y);
            final r = pixel.r; // <-- int (0–255)
            final g = pixel.g;
            final b = pixel.b;
            return [r, g, b]; // Array of [R, G, B] integers
          }),
        ),
      );

      // Output tetap float untuk menampung skor/logits
      final output = List.filled(
        outputTensor.shape[1],
        0.0,
      ).reshape([1, outputTensor.shape[1]]);

      // Jalankan inferensi
      _interpreter!.run(input, output);

      // --- PERBAIKAN CONFIDENCE: Softmax ---

      // 1. Ekstrak skor mentah (logits) dari output tensor
      final List<double> rawScores = (output[0] as List<dynamic>)
          .map(
            (e) => (e as num).toDouble(),
          ) // Konversi setiap elemen ke num, lalu ke double
          .toList();

      // 2. Terapkan Softmax untuk mendapatkan probabilitas (0.0 - 1.0)
      final probabilities = _softmax(
        rawScores,
      ); // Sekarang ini adalah List<double> yang benar

      // 3. Konversi probabilitas ke Map
      final Map<String, double> results = {};
      for (int i = 0; i < _labels.length && i < probabilities.length; i++) {
        results[_labels[i]] = probabilities[i];
      }

      // ------------------------------------

      // Urutkan berdasarkan confidence tertinggi
      final sortedResults = Map.fromEntries(
        results.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      log(
        '✅ Inference berhasil dijalankan (${sortedResults.keys.first}, Confidence: ${sortedResults.values.first * 100}%)',
      );
      return sortedResults;
    } catch (e) {
      log('❌ Error inferenceImageFile: $e');
      return {};
    }
  }

  // Fungsi umum untuk classify (dipanggil Provider)
  Future<Map<String, double>> classify(File image) async {
    if (_interpreter == null || _labels.isEmpty) {
      await loadModel();
    }
    // Karena Anda hanya perlu 3 teratas, Anda bisa memprosesnya di sini atau di UI.
    // Fungsi ini sekarang mengembalikan probabilitas 0.0 - 1.0 yang benar.
    final result = await inferenceImageFile(image);

    // Ambil hanya 3 teratas (jika diperlukan)
    final top3 = Map.fromEntries(result.entries.take(3));
    return top3;
  }

  // Tutup proses (Isolate)
  Future<void> close() async {
    await isolateInference.close();
    log(' IsolateInference ditutup');
  }
}
