import 'package:http/http.dart' as http;

/// Intercepts HTTP requests to inject the Google OAuth bearer token.
/// This is required by the `googleapis` package to securely access private Drive files.
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}