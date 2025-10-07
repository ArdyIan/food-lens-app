import 'dart:io';
import 'package:flutter/material.dart';

class ResultPage extends StatelessWidget {
  final File imageFile;
  final Map<String, num> classifications;

  // Definisikan konstanta untuk logika filter
  static const String backgroundLabel = '__background__';
  static const double lowConfidenceThreshold = 0.25;
  static const double backgroundMinConfidence = 0.25;

  const ResultPage({
    super.key,
    required this.imageFile,
    required this.classifications,
  });

  @override
  Widget build(BuildContext context) {
    // Sortir hasil dari tertinggi ke terendah
    final topResults = classifications.entries.toList()
      ..sort((a, b) => b.value.toDouble().compareTo(a.value.toDouble()));

    // Dapatkan confidence score untuk kelas __background__
    final double backgroundConfidence =
        classifications[backgroundLabel]?.toDouble() ?? 0.0;

    // Filter top 3: hanya ambil 3 label yang BUKAN __background__
    final List<MapEntry<String, double>> filteredTop3 = topResults
        .where((entry) => entry.key != backgroundLabel)
        .take(3)
        .map((e) => MapEntry(e.key, e.value.toDouble()))
        .toList();

    // Confidence tertinggi dari kelas makanan
    final double maxFoodConfidence = filteredTop3.isNotEmpty
        ? filteredTop3.first.value
        : 0.0;

    //LOGIKA PENENTUAN STATUS HASIL

    //  Terlalu bingung (Confidence teratas makanan di bawah threshold)
    final bool isHighlyConfused = maxFoodConfidence < lowConfidenceThreshold;

    // Kasus: Dominan non-food (Background > maxFoodConfidence)
    final bool isNonFoodDominant =
        backgroundConfidence >= backgroundMinConfidence &&
        backgroundConfidence > maxFoodConfidence;

    // Gabungkan skenario non-food
    final bool isNonFoodScenario = isHighlyConfused || isNonFoodDominant;

    String statusMessage = "";
    List<Widget> resultWidgets = [];

    if (isNonFoodScenario) {
      statusMessage = "Objek tidak teridentifikasi sebagai makanan.";

      resultWidgets.add(
        const Text(
          "Hasil prediksi tidak meyakinkan. Silakan coba gambar makanan yang jelas.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.redAccent, fontSize: 16),
        ),
      );

      if (backgroundConfidence > 0.01) {
        resultWidgets.add(
          Text(
            "Background Confidence: ${(backgroundConfidence * 100).toStringAsFixed(2)}%",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        );
      }
    } else {
      statusMessage = "Hasil Identifikasi Terbaik:";

      resultWidgets = filteredTop3
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "${entry.key} - Confidence: ${(entry.value * 100).toStringAsFixed(2)}%",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          )
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hasil Klasifikasi"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image yang diklasifikasi
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                imageFile,
                width: 300,
                height: 300,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),

            // Tampilkan status/pesan
            Text(
              statusMessage,
              style: TextStyle(
                color: isNonFoodScenario ? Colors.redAccent : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Tampilkan hasil/confidence
            ...resultWidgets,

            const SizedBox(height: 40),

            // Button "Coba Lagi"
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Coba Lagi"),
            ),
          ],
        ),
      ),
    );
  }
}
