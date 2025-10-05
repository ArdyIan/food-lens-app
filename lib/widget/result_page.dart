import 'dart:io';
import 'package:flutter/material.dart';

class ResultPage extends StatelessWidget {
  final File imageFile;
  final Map<String, num> classifications;
  const ResultPage({
    super.key,
    required this.imageFile,
    required this.classifications,
  });

  @override
  Widget build(BuildContext context) {
    final topResults = classifications.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top3 = topResults.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hasil Klasifikasi"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Container(
        color: Colors.black,
        width: double.infinity,
        padding: EdgeInsetsDirectional.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // image that calssifite
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

            //label dan confidence (top 3)
            ...top3.map(
              (entry) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "${entry.key} - Confidence: ${(entry.value * 100).toStringAsFixed(2)}%",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),

            SizedBox(height: 40),

            //button "coba lagi"
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: Icon(Icons.refresh),
              label: Text("Coba Lagi"),
            ),
          ],
        ),
      ),
    );
  }
}
