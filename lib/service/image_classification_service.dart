import 'dart:developer';
import 'dart:isolate';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_classification_litert/service/isolate_inference.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'isolate_inference.dart';

class ImageClassificationService {
  // Path Model dan Label
  final String _modelPath = 'assets/mobilenet.tflite';
  final String _labelsPath = 'assets/labels.txt';

  // Variabel utama
  Interpreter? _interpreter;
  List<String> _labels = [];
  late Tensor inputTensor;
  late Tensor outputTensor;
  late final IsolateInference isolateInference;

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

  //  Load Labels
  Future<void> _loadLabels() async {
    try {
      final labelTxt = await rootBundle.loadString(_labelsPath);
      _labels = labelTxt.split('\n');
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

  // Inferensi Kamera (Opsional)
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

  // Inferensi dari File Gambar

  Future<Map<String, double>> inferenceImageFile(File imageFile) async {
    try {
      if (_interpreter == null) await loadModel();

      final imageData = File(imageFile.path).readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) throw Exception('Gagal membaca gambar');

      // Resize ke 224x224 (sesuai input model)
      final resizedImage = img.copyResize(image, width: 224, height: 224);

      // Konversi ke float32 & normalisasi 0–1
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(224, (x) {
            final pixel = resizedImage.getPixel(x, y);
            final r = pixel.r / 255.0;
            final g = pixel.g / 255.0;
            final b = pixel.b / 255.0;

            return [r, g, b];
          }),
        ),
      );

      final output = List.filled(
        outputTensor.shape[1],
        0.0,
      ).reshape([1, outputTensor.shape[1]]);

      _interpreter!.run(input, output);

      // Cocokkan hasil dengan label
      final Map<String, double> results = {};
      for (int i = 0; i < _labels.length && i < output[0].length; i++) {
        results[_labels[i]] = output[0][i];
      }

      // Urutkan berdasarkan confidence tertinggi
      final sortedResults = Map.fromEntries(
        results.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      log(' Inference berhasil dijalankan (${sortedResults.keys.first})');
      return sortedResults;
    } catch (e) {
      log(' Error inferenceImageFile: $e');
      return {};
    }
  }

  // Fungsi umum untuk classify (dipanggil Provider)

  Future<Map<String, double>> classify(File image) async {
    if (_interpreter == null || _labels.isEmpty) {
      await loadModel();
    }
    final result = await inferenceImageFile(image);
    return result;
  }

  // Tutup proses (Isolate)

  Future<void> close() async {
    await isolateInference.close();
    log('🧹 IsolateInference ditutup');
  }
}
