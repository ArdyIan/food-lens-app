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
  //  setup the static variable
  final modelPath = 'assets/mobilenet.tflite';
  final labelsPath = 'assets/labels.txt';

  late final Interpreter interpreter;
  late final List<String> labels;
  late Tensor inputTensor;
  late Tensor outputTensor;
  late final IsolateInference isolateInference;

  // load model
  Future<void> _loadModel() async {
    final options = InterpreterOptions()
      ..useNnApiForAndroid = true
      ..useMetalDelegateForIOS = true;

    // Load model from assets
    interpreter = await Interpreter.fromAsset(modelPath, options: options);
    // Get tensor input shape [1, 224, 224, 3]
    inputTensor = interpreter.getInputTensors().first;
    // Get tensor output shape [1, 1001]
    outputTensor = interpreter.getOutputTensors().first;

    log('Interpreter loaded successfully');
  }

  //  load labels from assets
  Future<void> _loadLabels() async {
    final labelTxt = await rootBundle.loadString(labelsPath);
    labels = labelTxt.split('\n');
  }

  // run init function
  Future<void> initHelper() async {
    _loadLabels();
    _loadModel();
    // define a Isolate inference
    isolateInference = IsolateInference();
    await isolateInference.start();
  }

  //  inference camera frame
  Future<Map<String, double>> inferenceCameraFrame(
    CameraImage cameraImage,
  ) async {
    var isolateModel = InferenceModel(
      cameraImage,
      interpreter.address,
      labels,
      inputTensor.shape,
      outputTensor.shape,
    );

    ReceivePort responsePort = ReceivePort();
    isolateInference.sendPort.send(
      isolateModel..responsePort = responsePort.sendPort,
    );
    // get inference result.
    var results = await responsePort.first;
    return results;
  }

  // inferencec from file to image (camera / gallery)
  Future<Map<String, double>> inferenceImageFile(File imageFile) async {
    try {
      // read image file
      final imageData = File(imageFile.path).readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) throw Exception('Gagal membaca gambar');

      // Resize to 224x224 (size of input model)
      final resizedImage = img.copyResize(image, width: 224, height: 224);

      // convert to float43 format and normalize (0–1)
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(224, (x) {
            final pixel = resizedImage.getPixel(x, y);
            return [(pixel.r / 255.0), (pixel.g / 255.0), (pixel.b / 255.0)];
          }),
        ),
      );

      //  output tensor
      final output = List.filled(
        outputTensor.shape[1],
        0.0,
      ).reshape([1, outputTensor.shape[1]]);

      // run inference
      interpreter.run(input, output);

      //  match the result with label
      final Map<String, double> results = {};
      for (int i = 0; i < labels.length && i < output[0].length; i++) {
        results[labels[i]] = output[0][i];
      }

      //  sort result based on higher  confidence 
      final sortedResults = Map.fromEntries(
        results.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
      );

      log(' Inference berhasil dijalankan');
      return sortedResults;
    } catch (e) {
      print('Error inferenceImageFile: $e');
      return {};
    }
  }

  //  close the process from the service
  Future<void> close() async {
    await isolateInference.close();
  }
}
