import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_classification_litert/controller/image_classification_provider.dart';
import 'package:image_classification_litert/service/image_classification_service.dart';
import 'package:image_classification_litert/widget/camera_view.dart';
import 'package:provider/provider.dart';
import 'package:image_classification_litert/widget/result_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Image Classification App'),
      ),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: MultiProvider(
            providers: [
              Provider(create: (context) => ImageClassificationService()),
              ChangeNotifierProvider(
                create: (context) => ImageClassificationViewmodel(
                  context.read<ImageClassificationService>(),
                ),
              ),
            ],
            child: const _HomeBody(),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody();

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  late final readViewmodel = context.read<ImageClassificationViewmodel>();

  @override
  void dispose() {
    Future.microtask(() async => await readViewmodel.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ImageClassificationViewmodel>();
    final selectedImage = viewmodel.selectedImage;

    return Center(
      child: selectedImage == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.image_outlined,
                  color: Colors.white70,
                  size: 100,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    await viewmodel.takePictureWithCamera();
                    if (viewmodel.selectedImage != null &&
                        viewmodel.classifications.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResultPage(
                            imageFile: viewmodel.selectedImage!,
                            classifications: viewmodel.classifications,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Ambil dari Kamera"),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await viewmodel.pickImageFromGallery();
                    if (viewmodel.selectedImage != null &&
                        viewmodel.classifications.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResultPage(
                            imageFile: viewmodel.selectedImage!,
                            classifications: viewmodel.classifications,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Pilih dari Galeri"),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: FileImage(selectedImage),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    viewmodel.clearImage();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("Ambil Ulang"),
                ),
              ],
            ),
    );
  }
}