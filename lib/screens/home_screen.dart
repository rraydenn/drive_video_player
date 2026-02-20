import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

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
  GoogleSignInAccount? _currentUser;
  bool _isInitialized = false;

  // We now keep a master list, and a filtered list for the UI
  List<drive.File> _allVideoFiles = [];
  List<drive.File> _displayedFiles = [];
  bool _isLoadingVideos = false;

  String _searchQuery = '';
  SortMode _sortMode = SortMode.titleAsc;

  final List<String> _scopes = [drive.DriveApi.driveReadonlyScope];

  @override
  void initState() {
    super.initState();
    _initGoogleSignIn();
  }

  // Helper to remove file extensions (e.g. .mp4, .mkv)
  String _cleanName(String? name) {
    if (name == null) return 'Unknown Video';
    return name.replaceAll(RegExp(r'\.[^.]+$'), '');
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(serverClientId: dotenv.env['WEB_CLIENT_ID']!);
      setState(() => _isInitialized = true);

      _googleSignIn.authenticationEvents.listen((event) {
        setState(() {
          _currentUser = switch (event) {
            GoogleSignInAuthenticationEventSignIn() => event.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
        });
        if (_currentUser != null) {
          _fetchVideos();
        } else {
          _allVideoFiles.clear();
          _displayedFiles.clear();
        }
      });
      await _googleSignIn.attemptLightweightAuthentication();
    } catch (e) {
      debugPrint("Initialization warning: $e");
    }
  }

  Future<void> _handleSignIn() async {
    if (!_isInitialized) return;
    try {
      await _googleSignIn.authenticate();
      final authClient = _googleSignIn.authorizationClient;
      var authorization = await authClient.authorizationForScopes(_scopes);
      if (authorization == null) await authClient.authorizeScopes(_scopes);
    } catch (error) {
      debugPrint("Error signing in: $error");
    }
  }

  Future<void> _handleSignOut() async {
    await _googleSignIn.disconnect();
    setState(() => _currentUser = null);
  }

  Future<void> _fetchVideos() async {
    if (_currentUser == null) return;
    setState(() => _isLoadingVideos = true);

    try {
      final authClient = _googleSignIn.authorizationClient;
      var authorization = await authClient.authorizationForScopes(_scopes);
      authorization ??= await authClient.authorizeScopes(_scopes);

      final headers = {'Authorization': 'Bearer ${authorization.accessToken}'};
      final client = GoogleAuthClient(headers);
      final driveApi = drive.DriveApi(client);
      final String folderId = dotenv.env['FOLDER_ID']!;

      // We added modifiedTime to the requested fields so we can sort by date
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

  // --- NEW SEARCH & SORT LOGIC ---
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
        case SortMode.dateDesc: return dateB.compareTo(dateA); // Newest first
        case SortMode.dateAsc: return dateA.compareTo(dateB);  // Oldest first
      }
    });

    setState(() {
      _displayedFiles = temp;
    });
  }

  // --- TRUE SHUFFLE LOGIC ---
  Future<void> _playTrueRandom() async {
    if (_displayedFiles.isEmpty) return;

    // Create a deeply shuffled copy of whatever list we are currently looking at
    final shuffledList = List<drive.File>.from(_displayedFiles)..shuffle();

    final authClient = _googleSignIn.authorizationClient;
    final auth = await authClient.authorizationForScopes(_scopes);

    if (auth != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoList: shuffledList,
            currentIndex: 0, // Start at the beginning of the new shuffled list!
            accessToken: auth.accessToken,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive Player'),
        actions: [
          if (_currentUser != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: _handleSignOut,
            )
        ],
      ),
      floatingActionButton: (_currentUser != null && _displayedFiles.isNotEmpty)
          ? FloatingActionButton(
        onPressed: _playTrueRandom,
        tooltip: 'Shuffle Play All',
        child: const Icon(Icons.shuffle),
      )
          : null,
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : _currentUser == null
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
          // --- NEW SEARCH & SORT BAR ---
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
          // The Video List
          Expanded(
            child: ListView.builder(
              itemCount: _displayedFiles.length,
              itemBuilder: (context, index) {
                final video = _displayedFiles[index];
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(_cleanName(video.name)),
                  onTap: () async {
                    final authClient = _googleSignIn.authorizationClient;
                    final auth = await authClient.authorizationForScopes(_scopes);

                    if (auth != null) {
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VideoPlayerScreen(
                            videoList: _displayedFiles,
                            currentIndex: index,
                            accessToken: auth.accessToken,
                          ),
                        ),
                      );
                    }
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