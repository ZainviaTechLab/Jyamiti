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
  // Placeholder URL for your Digital Ocean backend endpoint that returns a short-lived access token
  static const String _tokenEndpoint = 'https://api.jyamitimath.com/oauth/token';

  /// Fetches a short-lived access token from the backend.
  Future<String> _getAccessToken() async {
    try {
      // Mock implementation: Normally you'd do an http.get or http.post here.
      // final response = await http.get(Uri.parse(_tokenEndpoint));
      // final data = jsonDecode(response.body);
      // return data['access_token'];
      
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 1));
      
      // We return a dummy token for now since the backend doesn't exist yet.
      return 'dummy_access_token_from_backend';
    } catch (e) {
      throw Exception('Failed to fetch access token from backend: $e');
    }
  }

  /// Uploads a video file to Google Drive.
  Future<void> uploadToDrive(File video, String fileName) async {
    final token = await _getAccessToken();
    final client = GoogleAuthClient(token);
    
    try {
      final driveApi = drive.DriveApi(client);
      
      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = ['root']; // Or a specific shared folder ID
        
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

  /// Uploads a video file to YouTube.
  Future<void> uploadToYouTube({
    required File video,
    required String title,
    required String description,
    required String privacyStatus,
    required String categoryId,
    required List<String> tags,
    required bool madeForKids,
  }) async {
    final token = await _getAccessToken();
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
        return;
      }
      
      await youtubeApi.videos.insert(
        videoMetadata,
        ['snippet', 'status'],
        uploadMedia: media,
      );
    } finally {
      client.close();
    }
  }
}
