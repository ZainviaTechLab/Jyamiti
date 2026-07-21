import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class FileViewerScreen extends StatelessWidget {
  final String url;
  final String filename;
  final bool isDownloadable;

  const FileViewerScreen({
    super.key, 
    required this.url, 
    required this.filename,
    this.isDownloadable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPdf = filename.toLowerCase().endsWith('.pdf');

    return Scaffold(
      backgroundColor: context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(filename, style: TextStyle(color: context.textColor)),
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          if (isDownloadable)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download File',
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch download URL')));
                  }
                }
              },
            ),
        ],
      ),
      body: isPdf
          ? SfPdfViewer.network(url)
          : Center(
              child: InteractiveViewer(
                child: Image.network(
                  url,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const CircularProgressIndicator(color: Color(0xFF6366F1));
                  },
                  errorBuilder: (context, error, stackTrace) => const Text('Error loading image', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
    );
  }
}
