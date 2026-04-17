import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/google_auth_client.dart';
import 'player_screen.dart';

enum SortMode { titleAsc, titleDesc, dateDesc, dateAsc }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _isInitialized = false;
  bool _isAuthenticated = false;
  String? _accessToken;
  auth_io.AuthClient? _desktopAuthClient;

  List<drive.File> _allVideoFiles = [];
  List<drive.File> _displayedFiles = [];
  bool _isLoadingVideos = false;

  String _searchQuery = '';
  SortMode _sortMode = SortMode.titleAsc;

  final List<String> _scopes = [drive.DriveApi.driveReadonlyScope];

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  String _cleanName(String? name) {
    if (name == null) return 'Unknown Video';
    return name.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  Future<void> _initAuth() async {
    try {
      if (_isDesktop) {
        final prefs = await SharedPreferences.getInstance();
        final refreshToken = prefs.getString('drive_refresh_token');

        if (refreshToken != null) {
          final clientId = auth_io.ClientId(dotenv.env['DESKTOP_CLIENT_ID']!, dotenv.env['DESKTOP_CLIENT_SECRET']!);
          final credentials = auth_io.AccessCredentials(
            auth_io.AccessToken('Bearer', '', DateTime.now().toUtc().subtract(const Duration(days: 1))),
            refreshToken,
            _scopes,
          );

          try {
            final newCreds = await auth_io.refreshCredentials(clientId, credentials, http.Client());
            setState(() {
              _isAuthenticated = true;
              _accessToken = newCreds.accessToken.data;
            });
            _fetchVideos();
          } catch (e) {
            debugPrint("Session expirée : $e");
            await prefs.remove('drive_refresh_token');
          }
        }
        setState(() => _isInitialized = true);
      } else {
        await _googleSignIn.initialize(serverClientId: dotenv.env['WEB_CLIENT_ID']!);
        _googleSignIn.authenticationEvents.listen((event) async {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            var auth = await event.user.authorizationClient.authorizationForScopes(_scopes);
            setState(() {
              _isAuthenticated = true;
              _accessToken = auth?.accessToken;
            });
            if (_accessToken != null) _fetchVideos();
          } else {
            _handleSignOutState();
          }
        });
        await _googleSignIn.attemptLightweightAuthentication();
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint("Initialization warning: $e");
      setState(() => _isInitialized = true);
    }
  }

  Future<void> _handleSignIn() async {
    if (!_isInitialized) return;

    try {
      if (_isDesktop) {
        final clientId = auth_io.ClientId(dotenv.env['DESKTOP_CLIENT_ID']!, dotenv.env['DESKTOP_CLIENT_SECRET']!);
        _desktopAuthClient = await auth_io.clientViaUserConsent(clientId, _scopes, (url) async {
          if (!await launchUrl(Uri.parse(url))) {
            throw Exception('Impossible d\'ouvrir le navigateur pour $url');
          }
        });

        final refreshToken = _desktopAuthClient!.credentials.refreshToken;
        if (refreshToken != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('drive_refresh_token', refreshToken);
        }

        setState(() {
          _isAuthenticated = true;
          _accessToken = _desktopAuthClient!.credentials.accessToken.data;
        });
        _fetchVideos();
      } else {
        final account = await _googleSignIn.authenticate();
        var auth = await account.authorizationClient.authorizationForScopes(_scopes);
        auth ??= await account.authorizationClient.authorizeScopes(_scopes);
        setState(() {
          _isAuthenticated = true;
          _accessToken = auth?.accessToken;
        });
        _fetchVideos();
                  }
    } catch (error) {
      debugPrint("Error signing in: $error");
    }
  }

  Future<void> _handleSignOut() async {
    if (_isDesktop) {
      _desktopAuthClient?.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('drive_refresh_token');
    } else {
      await _googleSignIn.disconnect();
    }
    _handleSignOutState();
  }

  void _handleSignOutState() {
    setState(() {
      _isAuthenticated = false;
      _accessToken = null;
      _desktopAuthClient = null;
      _allVideoFiles.clear();
      _displayedFiles.clear();
    });
  }

  Future<void> _fetchVideos() async {
    if (!_isAuthenticated || _accessToken == null) return;
    setState(() => _isLoadingVideos = true);

    try {
      final headers = {'Authorization': 'Bearer $_accessToken'};
      final client = GoogleAuthClient(headers);
      final driveApi = drive.DriveApi(client);
      final String folderId = dotenv.env['FOLDER_ID']!;

      final drive.FileList fileList = await driveApi.files.list(
        q: "'$folderId' in parents and mimeType contains 'video/' and trashed=false",
        $fields: "files(id, name, mimeType, modifiedTime)",
        pageSize: 1000,
      );

      _allVideoFiles = fileList.files ?? [];
      _applySearchAndSort();

    } catch (e) {
      debugPrint("Error fetching videos: $e");
    } finally {
      setState(() => _isLoadingVideos = false);
    }
  }

  void _applySearchAndSort() {
    var temp = List<drive.File>.from(_allVideoFiles);

    if (_searchQuery.isNotEmpty) {
      temp = temp.where((f) =>
          (f.name ?? '').toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }

    temp.sort((a, b) {
      final nameA = a.name?.toLowerCase() ?? '';
      final nameB = b.name?.toLowerCase() ?? '';
      final dateA = a.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0);

      switch (_sortMode) {
        case SortMode.titleAsc: return nameA.compareTo(nameB);
        case SortMode.titleDesc: return nameB.compareTo(nameA);
        case SortMode.dateDesc: return dateB.compareTo(dateA);
        case SortMode.dateAsc: return dateA.compareTo(dateB);
      }
    });

    setState(() {
      _displayedFiles = temp;
    });
  }

  void _playTrueRandom() {
    if (_displayedFiles.isEmpty || _accessToken == null) return;

    final shuffledList = List<drive.File>.from(_displayedFiles)..shuffle();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoList: shuffledList,
          currentIndex: 0,
          accessToken: _accessToken!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive Player'),
        actions: [
          if (_isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: _handleSignOut,
            )
        ],
      ),
      floatingActionButton: (_isAuthenticated && _displayedFiles.isNotEmpty)
          ? FloatingActionButton(
        onPressed: _playTrueRandom,
        tooltip: 'Shuffle Play All',
        child: const Icon(Icons.shuffle),
      )
          : null,
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : !_isAuthenticated
          ? Center(
        child: ElevatedButton(
          onPressed: _handleSignIn,
          child: const Text('Sign in with Google'),
        ),
      )
          : _isLoadingVideos
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search videos...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _applySearchAndSort();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<SortMode>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort List',
                  onSelected: (SortMode mode) {
                    setState(() => _sortMode = mode);
                    _applySearchAndSort();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: SortMode.titleAsc, child: Text('Title (A-Z)')),
                    PopupMenuItem(value: SortMode.titleDesc, child: Text('Title (Z-A)')),
                    PopupMenuItem(value: SortMode.dateDesc, child: Text('Newest First')),
                    PopupMenuItem(value: SortMode.dateAsc, child: Text('Oldest First')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _displayedFiles.length,
              itemBuilder: (context, index) {
                final video = _displayedFiles[index];
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(_cleanName(video.name)),
                  onTap: () {
                    if (_accessToken == null) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoPlayerScreen(
                          videoList: _displayedFiles,
                          currentIndex: index,
                          accessToken: _accessToken!,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}