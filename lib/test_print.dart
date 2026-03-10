import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TestPrint extends StatelessWidget {
  const TestPrint({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          child: const Text("Test Print"),
          onPressed: () async {
            final doc = pw.Document();
            doc.addPage(
              pw.Page(
                build: (context) => pw.Center(
                  child: pw.Text("Printing works"),
                ),
              ),
            );

            await Printing.layoutPdf(
              onLayout: (format) async => doc.save(),
            );
          },
        ),
      ),
    );
  }
}