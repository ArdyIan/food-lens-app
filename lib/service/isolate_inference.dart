// menjalankan proses inference.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math; // Diperlukan untuk fungsi exp() di Softmax

import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image_classification_litert/utils/image_utils.dart';
import 'package:image/image.dart' as image_lib;

// create a class isolate
class IsolateInference {
  //  setup a state
  static const String _debugName = "TFLITE_INFERENCE";
  final ReceivePort _receivePort = ReceivePort();
  late Isolate _isolate;
  late SendPort _sendPort;
  SendPort get sendPort => _sendPort;

  // open the new thread and create a static function
  Future<void> start() async {
    _isolate = await Isolate.spawn<SendPort>(
      entryPoint,
      _receivePort.sendPort,
      debugName: _debugName,
    );
    _sendPort = await _receivePort.first;
  }

  // --- FUNGSI SOFTMAX UNTUK ISOLATE ---
  // Fungsi ini harus tersedia di dalam konteks Isolate
  static List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];

    // 1. Hitung eksponensial (e^score)
    final exp = logits.map((e) => math.exp(e)).toList();
    // 2. Hitung jumlah semua eksponensial
    final sumExp = exp.reduce((a, b) => a + b);

    if (sumExp == 0) return logits.map((_) => 0.0).toList();

    // 3. Bagi setiap eksponensial dengan total sum
    return exp.map((e) => e / sumExp).toList();
  }
  // ------------------------------------

  static void entryPoint(SendPort sendPort) async {
    final port = ReceivePort();
    sendPort.send(port.sendPort);

    await for (final InferenceModel isolateModel in port) {
      final cameraImage = isolateModel.cameraImage!;
      final inputShape = isolateModel.inputShape;

      // 1. Pra-pemrosesan Gambar (Kembali ke uint8/integer)
      final imageMatrix = _imagePreProcessing(cameraImage, inputShape);

      // Input adalah List<num> (berisi integer)
      final input = [imageMatrix];

      // Output: Model mengembalikan skor/logits (asumsikan List<num> atau List<int> di sini)
      final output = [List<num>.filled(isolateModel.outputShape[1], 0)];
      final address = isolateModel.interpreterAddress;

      // Jalankan inferensi
      final List<double> rawScores = _runInference(input, output, address);

      // 2. Normalisasi menggunakan SOFTMAX (Perbaikan Kritis)
      final probabilities = _softmax(rawScores);

      // Konversi probabilitas (0.0 - 1.0) ke Map
      final keys = isolateModel.labels;
      var classification = Map.fromIterables(keys, probabilities);

      // Hapus yang confidence-nya 0
      classification.removeWhere((key, value) => value == 0);

      // Urutkan berdasarkan confidence tertinggi
      final sortedClassification = Map.fromEntries(
        classification.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
      );

      //  send the result to main thread
      isolateModel.responsePort.send(sortedClassification);
    }
  }

  //  close every thread that might be open
  Future<void> close() async {
    _isolate.kill();
    _receivePort.close();
  }

  // 3. Pra-pemrosesan Gambar (Kembali ke integer [0, 255])
  static List<List<List<num>>> _imagePreProcessing(
    // Tipe Output tetap List<num>
    CameraImage cameraImage,
    List<int> inputShape,
  ) {
    image_lib.Image? img;
    img = ImageUtils.convertCameraImage(cameraImage);

    // resize original image to match model shape.
    image_lib.Image imageInput = image_lib.copyResize(
      img!,
      width: inputShape[1],
      height: inputShape[2],
    );

    if (Platform.isAndroid) {
      imageInput = image_lib.copyRotate(imageInput, angle: 90);
    }

    final imageMatrix = List.generate(
      imageInput.height,
      (y) => List.generate(imageInput.width, (x) {
        final pixel = imageInput.getPixel(x, y);
        // Mengembalikan nilai integer RGB (0-255)
        return [pixel.r, pixel.g, pixel.b];
      }),
    );
    return imageMatrix;
  }

  // 4. Menjalankan Inferensi dan Mengkonversi Output Mentah
  static List<double> _runInference(
    List<List<List<List<num>>>> input,
    List<List<num>> output, // Wadah output menggunakan List<num>
    int interpreterAddress,
  ) {
    Interpreter interpreter = Interpreter.fromAddress(interpreterAddress);

    // Pastikan wadah output yang digunakan di interpreter.run() adalah List<List<num>>
    final rawOutput = [List<num>.filled(output[0].length, 0)];

    interpreter.run(input, rawOutput);

    // Ambil output mentah (List<num>) dan konversi ke List<double> untuk Softmax
    final List<double> result = rawOutput.first
        .map((e) => e.toDouble())
        .toList();
    return result;
  }
}

// create a model class
class InferenceModel {
  CameraImage? cameraImage;
  int interpreterAddress;
  List<String> labels;
  List<int> inputShape;
  List<int> outputShape;
  late SendPort responsePort;

  InferenceModel(
    this.cameraImage,
    this.interpreterAddress,
    this.labels,
    this.inputShape,
    this.outputShape,
  );
}
