import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/youtube/v3.dart' as youtube;

/// An authenticated HTTP client that attaches a Bearer token to all requests.
class GoogleAuthClient extends http.BaseClient {
  final String _token;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _client.send(request);
  }
}

class UploadService {
  // URL for your Digital Ocean backend endpoint that returns a short-lived access token
  static const String _tokenEndpoint = 'https://api.jyamitimath.com/api/oauth/google-token';

  Future<String> _getAccessToken(String scope) async {
    try {
      final response = await http.get(Uri.parse('$_tokenEndpoint?scope=$scope'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['access_token'] != null) {
          return data['access_token'];
        }
      }
      throw Exception('Failed to get token: ${response.body}');
    } catch (e) {
      // Fallback for testing if backend is not set up
      print('Using fallback dummy token. Error: $e');
      await Future.delayed(const Duration(seconds: 1));
      return 'dummy_access_token_from_backend';
    }
  }

  Future<List<Map<String, String>>> listDriveFolders() async {
    final token = await _getAccessToken('drive');
    if (token == 'dummy_access_token_from_backend') return [];
    
    final client = GoogleAuthClient(token);
    try {
      final driveApi = drive.DriveApi(client);
      final fileList = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and trashed=false",
        $fields: "files(id, name)",
      );
      
      return (fileList.files ?? []).map((file) => {
        'id': file.id ?? '',
        'name': file.name ?? '',
      }).toList();
    } finally {
      client.close();
    }
  }

  Future<String> createDriveFolder(String folderName) async {
    final token = await _getAccessToken('drive');
    if (token == 'dummy_access_token_from_backend') return 'dummy_folder_id';
    
    final client = GoogleAuthClient(token);
    try {
      final driveApi = drive.DriveApi(client);
      final fileMetadata = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';
        
      final folder = await driveApi.files.create(fileMetadata);
      return folder.id ?? '';
    } finally {
      client.close();
    }
  }

  /// Uploads a video file to Google Drive.
  Future<void> uploadToDrive(File video, String fileName, {String? folderId}) async {
    final token = await _getAccessToken('drive');
    final client = GoogleAuthClient(token);
    
    try {
      final driveApi = drive.DriveApi(client);
      
      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = [folderId ?? 'root'];
        
      final media = drive.Media(video.openRead(), video.lengthSync());
      
      // Mocking the actual upload to prevent unauthorized errors with dummy token
      if (token == 'dummy_access_token_from_backend') {
        await Future.delayed(const Duration(seconds: 2));
        return;
      }
      
      await driveApi.files.create(fileMetadata, uploadMedia: media);
    } finally {
      client.close();
    }
  }

  /// Uploads a video file to YouTube and returns the video ID.
  Future<String> uploadToYouTube({
    required File video,
    required String title,
    required String description,
    required String privacyStatus,
    required String categoryId,
    required List<String> tags,
    required bool madeForKids,
  }) async {
    final token = await _getAccessToken('youtube');
    final client = GoogleAuthClient(token);
    
    try {
      final youtubeApi = youtube.YouTubeApi(client);
      
      final videoMetadata = youtube.Video()
        ..snippet = (youtube.VideoSnippet()
          ..title = title
          ..description = description
          ..tags = tags
          ..categoryId = categoryId)
        ..status = (youtube.VideoStatus()
          ..privacyStatus = privacyStatus.toLowerCase()
          ..madeForKids = madeForKids);
          
      final media = youtube.Media(video.openRead(), video.lengthSync());
      
      // Mocking the actual upload to prevent unauthorized errors with dummy token
      if (token == 'dummy_access_token_from_backend') {
        await Future.delayed(const Duration(seconds: 2));
        return 'dummy_video_id';
      }
      
      final response = await youtubeApi.videos.insert(
        videoMetadata,
        ['snippet', 'status'],
        uploadMedia: media,
      );
      
      return response.id ?? '';
    } finally {
      client.close();
    }
  }
}
