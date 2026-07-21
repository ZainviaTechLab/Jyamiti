import 'dart:convert';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import '../../../../services/api_service.dart';

class DesktopUploadTab extends StatefulWidget {
  const DesktopUploadTab({super.key});

  @override
  State<DesktopUploadTab> createState() => _DesktopUploadTabState();
}

class _DesktopUploadTabState extends State<DesktopUploadTab> {
  final _formKey = GlobalKey<FormState>();
  final _versionCtrl = TextEditingController();
  final _buildCodeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isFetchingCurrent = false;
  bool _isUploading = false;
  
  Map<String, dynamic>? _currentVersionData;
  
  String? _selectedFileName;
  List<int>? _selectedFileBytes;
  int _selectedFileSize = 0;

  @override
  void initState() {
    super.initState();
    _fetchCurrentVersion();
  }

  @override
  void dispose() {
    _versionCtrl.dispose();
    _buildCodeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentVersion() async {
    setState(() => _isFetchingCurrent = true);
    try {
      final res = await ApiService.get('/updates/windows');
      if (res.statusCode == 200) {
        setState(() {
          _currentVersionData = jsonDecode(res.body);
          if (_currentVersionData != null) {
            final prevCode = _currentVersionData!['latestBuildCode'] ?? 0;
            _buildCodeCtrl.text = (prevCode + 1).toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching current version: $e');
    } finally {
      setState(() => _isFetchingCurrent = false);
    }
  }

  Map<String, String>? _parseMsixManifest(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.name == 'AppxManifest.xml') {
          final content = String.fromCharCodes(file.content);
          final match = RegExp(r'Version="(\d+)\.(\d+)\.(\d+)\.(\d+)"').firstMatch(content);
          if (match != null) {
            final major = match.group(1);
            final minor = match.group(2);
            final build = match.group(3);
            final revision = match.group(4);
            return {
              'version': '$major.$minor.$build',
              'buildCode': revision ?? '0',
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Error decoding MSIX manifest: $e');
    }
    return null;
  }

  Future<void> _publishUpdate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a desktop application file to upload.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final fields = {
        'platform': 'windows',
        'latestVersion': _versionCtrl.text.trim(),
        'latestBuildCode': _buildCodeCtrl.text.trim(),
        'releaseNotes': _notesCtrl.text.trim(),
      };

      final res = await ApiService.uploadWorksheet(
        '/updates',
        fields,
        _selectedFileBytes,
        _selectedFileName,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desktop update published successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Reset form
        setState(() {
          _selectedFileName = null;
          _selectedFileBytes = null;
          _selectedFileSize = 0;
          _versionCtrl.clear();
          _notesCtrl.clear();
        });
        _fetchCurrentVersion();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed (Status: ${res.statusCode})'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading update: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Widget _buildFilePickerZone() {
    return InkWell(
      onTap: () async {
        FilePickerResult? result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['exe', 'msi', 'zip', 'dmg', 'appx', 'msix'],
          withData: true,
        );
        if (result != null && result.files.single.bytes != null) {
          final name = result.files.single.name;
          final bytes = result.files.single.bytes;
          final size = result.files.single.size;
          
          setState(() {
            _selectedFileName = name;
            _selectedFileBytes = bytes;
            _selectedFileSize = size;
            
            String? detectedVersion;
            String? detectedBuildCode;
            
            final fullMatch = RegExp(r'v?(\d+\.\d+\.\d+)\+(\d+)').firstMatch(name);
            if (fullMatch != null) {
              detectedVersion = fullMatch.group(1);
              detectedBuildCode = fullMatch.group(2);
            } else {
              final verMatch = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch(name);
              if (verMatch != null) {
                detectedVersion = verMatch.group(1);
              }
            }
            
            if (name.toLowerCase().endsWith('.msix')) {
              final manifest = _parseMsixManifest(bytes!);
              if (manifest != null) {
                detectedVersion = manifest['version'];
                detectedBuildCode = manifest['buildCode'];
              }
            }
            
            if (detectedVersion != null) {
              _versionCtrl.text = detectedVersion;
            }
            if (detectedBuildCode != null) {
              _buildCodeCtrl.text = detectedBuildCode;
            }
          });
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: context.glassBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _selectedFileName != null
                ? const Color(0xFF10B981).withOpacity(0.5)
                : context.glassBorder,
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _selectedFileName != null
                  ? Icons.check_circle_rounded
                  : Icons.cloud_upload_rounded,
              color: _selectedFileName != null
                  ? const Color(0xFF10B981)
                  : const Color(0xFF6366F1),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _selectedFileName ?? 'Select Desktop Package File',
              style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _selectedFileName != null
                  ? '${(_selectedFileSize / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : 'Supports .exe, .msi, .msix, .zip, .dmg, .appx',
              style: TextStyle(
                color: context.textColor70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeVersion = _currentVersionData?['latestVersion'] ?? 'None';
    final activeBuild = _currentVersionData?['latestBuildCode']?.toString() ?? 'None';
    final notes = _currentVersionData?['releaseNotes'] ?? '';
    final downloadUrl = _currentVersionData?['downloadUrl'] ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desktop Version Manager',
              style: TextStyle(
                color: context.textColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Publish, track, and manage production updates for the desktop Windows/macOS clients.',
              style: TextStyle(color: context.textColor70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            
            // Current Active Version Details
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.glassBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.glassBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF818CF8),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT ACTIVE VERSION ON SERVER',
                          style: TextStyle(
                            color: context.textColor54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _isFetchingCurrent
                            ? const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Version: ',
                                        style: TextStyle(color: context.textColor70, fontSize: 15),
                                      ),
                                      Text(
                                        activeVersion,
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Build Code: ',
                                        style: TextStyle(color: context.textColor70, fontSize: 15),
                                      ),
                                      Text(
                                        activeBuild,
                                        style: TextStyle(
                                          color: context.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (notes.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Release Notes:',
                                      style: TextStyle(
                                        color: context.textColor70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      notes,
                                      style: TextStyle(color: context.textColor60, fontSize: 13),
                                    ),
                                  ],
                                  if (downloadUrl.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Download Link:',
                                      style: TextStyle(
                                        color: context.textColor70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    SelectableText(
                                      downloadUrl,
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fade(duration: 400.ms),
            
            const SizedBox(height: 32),
            
            // Upload New Build Section
            Text(
              'Publish New Build',
              style: TextStyle(
                color: context.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _isUploading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Color(0xFF6366F1)),
                          const SizedBox(height: 16),
                          Text(
                            'Uploading package and updating version settings...',
                            style: TextStyle(color: context.textColor70, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Please do not refresh or close this tab.',
                            style: TextStyle(color: context.textColor60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFilePickerZone(),
                        const SizedBox(height: 24),
                        
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _versionCtrl,
                                style: TextStyle(color: context.textColor),
                                decoration: InputDecoration(
                                  labelText: 'Release Version',
                                  labelStyle: TextStyle(color: context.textColor70),
                                  hintText: 'e.g. 1.0.6',
                                  hintStyle: TextStyle(color: context.textColor54),
                                  prefixIcon: const Icon(Icons.label_outline_rounded),
                                ),
                                validator: (v) => v!.isEmpty ? 'Version is required' : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _buildCodeCtrl,
                                style: TextStyle(color: context.textColor),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Build Code',
                                  labelStyle: TextStyle(color: context.textColor70),
                                  hintText: 'e.g. 7',
                                  hintStyle: TextStyle(color: context.textColor54),
                                  prefixIcon: const Icon(Icons.code_rounded),
                                ),
                                validator: (v) {
                                  if (v!.isEmpty) return 'Build Code is required';
                                  if (int.tryParse(v) == null) return 'Must be a number';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesCtrl,
                          style: TextStyle(color: context.textColor),
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'Release Notes / Changelog',
                            labelStyle: TextStyle(color: context.textColor70),
                            hintText: 'Describe new features, adjustments, or bug fixes...',
                            hintStyle: TextStyle(color: context.textColor54),
                          ),
                          validator: (v) => v!.isEmpty ? 'Changelog is required' : null,
                        ),
                        const SizedBox(height: 28),
                        
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.rocket_launch_rounded),
                          label: const Text(
                            'PUBLISH DESKTOP UPDATE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 1.0,
                            ),
                          ),
                          onPressed: _publishUpdate,
                        ),
                      ],
                    ),
                  ).animate().fade(duration: 400.ms, delay: 100.ms),
            
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
