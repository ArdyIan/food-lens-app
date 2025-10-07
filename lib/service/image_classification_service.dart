import 'dart:developer';
import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'isolate_inference.dart'; // Asumsi file custom Anda

class ImageClassificationService {
  final String _modelPath = 'assets/food_model.tflite';
  final String _labelsPath = 'assets/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = [];
  late Tensor inputTensor;
  late Tensor outputTensor;
  late final IsolateInference isolateInference;

  // FUNGSI SOFTMAX 
  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];

    final exp = logits.map((e) => math.exp(e)).toList();
    final sumExp = exp.reduce((a, b) => a + b);

    if (sumExp == 0) return logits.map((_) => 0.0).toList();

    return exp.map((e) => e / sumExp).toList();
  }

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

  Future<void> _loadLabels() async {
    try {
      final labelTxt = await rootBundle.loadString(_labelsPath);
      _labels = labelTxt.split('\n');
      _labels.removeWhere((label) => label.trim().isEmpty);
      log(' Label berhasil dimuat (${_labels.length} label)');
    } catch (e) {
      log(' Gagal memuat label: $e');
    }
  }

  Future<void> loadModel() async {
    await _loadLabels();
    await _loadModel();

    isolateInference = IsolateInference();
    await isolateInference.start();

    log(' Model dan label siap digunakan untuk inferensi');
  }

  // Inferensi Kamera (Menggunakan Isolate)
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
      // Hasil dari Isolate sudah harus melalui Softmax
      return results as Map<String, double>;
    } catch (e) {
      log(' Error inferenceCameraFrame: $e');
      return {};
    }
  }

  // Inferensi dari File Gambar (Thread Utama)
  Future<Map<String, double>> inferenceImageFile(File imageFile) async {
    try {
      if (_interpreter == null) await loadModel();

      log(' Input tensor type: ${inputTensor.type}');

      final imageData = File(imageFile.path).readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) throw Exception('Gagal membaca gambar');

      final resizedImage = img.copyResize(image, width: 224, height: 224);

      // Pra-pemrosesan: Kembalikan ke Integer [0, 255] (uint8)
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(224, (x) {
            final pixel = resizedImage.getPixel(x, y);
            return [pixel.r, pixel.g, pixel.b];
          }),
        ),
      );

      // Wadah output sebagai List<num>
      final output = [List<num>.filled(outputTensor.shape[1], 0)];

      _interpreter!.run(input, output);

      // Softmax dengan Konversi Tipe
      final List<double> rawScores = (output[0] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();

      log("raw scores : $rawScores");

      final probabilities = rawScores.map((e) => e / 255.0).toList();

      log("probabilites : $probabilities");

      final Map<String, double> results = {};
      for (int i = 0; i < _labels.length && i < probabilities.length; i++) {
        results[_labels[i]] = probabilities[i];
      }

      final sortedResults = Map.fromEntries(
        results.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      log(
        ' Inference berhasil dijalankan (${sortedResults.keys.first}, Confidence: ${sortedResults.values.first * 100}%)',
      );
      return sortedResults;
    } catch (e) {
      log(' Error inferenceImageFile: $e');
      return {};
    }
  }

  Future<Map<String, double>> classify(File image) async {
    if (_interpreter == null || _labels.isEmpty) {
      await loadModel();
    }
    final result = await inferenceImageFile(image);

    // Kembalikan semua hasil untuk diproses di ResultPage
    return result;
  }

  Future<void> close() async {
    await isolateInference.close();
    log(' IsolateInference ditutup');
  }
}
