import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/slide_deck_models.dart';
import 'api_service.dart';
import 'offline_sync_service.dart';

class SlideCacheService {
  static const String _decksKey = 'jyamiti_slide_decks_v1';
  static const String _progressKeyPrefix = 'jyamiti_slide_progress_';

  static SlideCacheService? _instance;
  static SlideCacheService get instance {
    _instance ??= SlideCacheService._();
    return _instance!;
  }

  SlideCacheService._();

  // Get all slide decks (fetches from API server with local offline fallback)
  Future<List<SlideDeck>> getSlideDecks() async {
    // 1. Try to fetch latest decks from backend API server
    try {
      final res = await ApiService.get('/slide-decks');
      if (res.statusCode == 200) {
        final List<dynamic> list = json.decode(res.body);
        final decks = list.map((x) => SlideDeck.fromMap(x as Map<String, dynamic>)).toList();
        await saveSlideDecks(decks); // Sync to local offline cache
        return decks;
      }
    } catch (_) {
      // Offline fallback
    }

    // 2. Offline local cache fallback
    final prefs = await SharedPreferences.getInstance();
    final String? rawJson = prefs.getString(_decksKey);

    if (rawJson == null || rawJson.isEmpty) {
      final seedDecks = _getInitialSeedDecks();
      await saveSlideDecks(seedDecks);
      return seedDecks;
    }

    try {
      final List<dynamic> list = json.decode(rawJson);
      return list.map((x) => SlideDeck.fromMap(x as Map<String, dynamic>)).toList();
    } catch (e) {
      final seedDecks = _getInitialSeedDecks();
      await saveSlideDecks(seedDecks);
      return seedDecks;
    }
  }

  // Fetch a single slide deck by id, straight from the backend -- used by
  // the live-class-presentation "follow the tutor's slides" viewer, which
  // only needs the ONE deck being shared rather than the full catalog
  // getSlideDecks() returns. No offline fallback here (unlike
  // getSlideDecks): a student following a live presentation is, by
  // definition, online and already inside a live video call.
  Future<SlideDeck?> getDeckById(String deckId) async {
    try {
      final res = await ApiService.get('/slide-decks/$deckId');
      if (res.statusCode == 200) {
        return SlideDeck.fromMap(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // Save all slide decks
  Future<void> saveSlideDecks(List<SlideDeck> decks) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = json.encode(decks.map((d) => d.toMap()).toList());
    await prefs.setString(_decksKey, jsonStr);
  }

  // Save single slide deck (posts to backend server API or enqueues offline sync)
  Future<void> saveDeck(SlideDeck deck) async {
    try {
      final res = await ApiService.post('/slide-decks', deck.toMap());
      if (res.statusCode != 200 && res.statusCode != 201) {
        await OfflineSyncService.instance.enqueueRequest('/slide-decks', deck.toMap());
      }
    } catch (_) {
      await OfflineSyncService.instance.enqueueRequest('/slide-decks', deck.toMap());
    }
  }

  // Delete slide deck (removes from backend server and clears local offline cache)
  Future<void> deleteDeck(String deckId) async {
    try {
      final res = await ApiService.delete('/slide-decks/$deckId');
      if (res.statusCode != 200) {
        await OfflineSyncService.instance.enqueueRequest('/slide-decks', {'id': deckId}, method: 'DELETE');
      }
    } catch (_) {
      await OfflineSyncService.instance.enqueueRequest('/slide-decks', {'id': deckId}, method: 'DELETE');
    }

    // Clear from local offline cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? rawJson = prefs.getString(_decksKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> list = json.decode(rawJson);
        final decks = list.map((x) => SlideDeck.fromMap(x as Map<String, dynamic>)).toList();
        decks.removeWhere((d) => d.id == deckId);
        await saveSlideDecks(decks);
      }
    } catch (_) {}
  }

  // Load student slide progress for a deck
  Future<SlideProgress> getProgress(String deckId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('$_progressKeyPrefix$deckId');
    if (raw == null || raw.isEmpty) {
      return SlideProgress(
        deckId: deckId,
        timeSpentPerSlide: {},
        completedSlides: {},
        bookmarkedSlides: {},
        quizAnswers: {},
        slideDrawings: {},
        lastViewedSlideIndex: 0,
        lastUpdated: DateTime.now(),
      );
    }
    try {
      return SlideProgress.fromJson(raw);
    } catch (e) {
      return SlideProgress(
        deckId: deckId,
        timeSpentPerSlide: {},
        completedSlides: {},
        bookmarkedSlides: {},
        quizAnswers: {},
        slideDrawings: {},
        lastViewedSlideIndex: 0,
        lastUpdated: DateTime.now(),
      );
    }
  }

  // Save student slide progress (saves locally and syncs to backend server or enqueues offline sync)
  Future<void> saveProgress(SlideProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_progressKeyPrefix${progress.deckId}', progress.toJson());

    // Sync progress to backend server API or enqueue for offline sync
    try {
      final res = await ApiService.post('/slide-decks/${progress.deckId}/progress', progress.toMap());
      if (res.statusCode != 200 && res.statusCode != 201) {
        await OfflineSyncService.instance.enqueueRequest('/slide-decks/${progress.deckId}/progress', progress.toMap());
      }
    } catch (_) {
      await OfflineSyncService.instance.enqueueRequest('/slide-decks/${progress.deckId}/progress', progress.toMap());
    }
  }

  // Generate mock analytics report for Admin
  Future<List<SlideAnalyticsReport>> getAnalyticsForDeck(String deckId, String deckTitle, int totalSlides) async {
    final progress = await getProgress(deckId);
    
    // Add real student progress plus representative student cohort data
    final List<SlideAnalyticsReport> reports = [
      SlideAnalyticsReport(
        studentId: 'stu_current',
        studentName: 'Current Active Student',
        deckId: deckId,
        deckTitle: deckTitle,
        completionPercent: progress.calculateCompletionPercent(totalSlides),
        totalTimeSpentSeconds: progress.calculateTotalTimeSpentSeconds(),
        slideTimeSpent: progress.timeSpentPerSlide,
        quizScore: progress.quizAnswers.length,
        totalQuizzes: totalSlides > 0 ? (totalSlides / 2).ceil() : 1,
        lastActive: progress.lastUpdated,
      ),
      SlideAnalyticsReport(
        studentId: 'stu_01',
        studentName: 'Aarav Sharma',
        deckId: deckId,
        deckTitle: deckTitle,
        completionPercent: 1.0,
        totalTimeSpentSeconds: 420,
        slideTimeSpent: {0: 45, 1: 90, 2: 110, 3: 85, 4: 90},
        quizScore: 3,
        totalQuizzes: 3,
        lastActive: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      SlideAnalyticsReport(
        studentId: 'stu_02',
        studentName: 'Ananya Patel',
        deckId: deckId,
        deckTitle: deckTitle,
        completionPercent: 0.6,
        totalTimeSpentSeconds: 210,
        slideTimeSpent: {0: 30, 1: 65, 2: 115},
        quizScore: 2,
        totalQuizzes: 3,
        lastActive: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
    return reports;
  }

  // Initial Seed Slide Decks for demo & immediate testing
  List<SlideDeck> _getInitialSeedDecks() {
    return [
      SlideDeck(
        id: 'deck_geom_01',
        courseId: 'math_101',
        courseName: 'Advanced Geometry',
        title: 'Pythagorean Theorem & Right Triangles',
        description: 'Interactive course slides covering fundamental geometric proofs, formulas, code demos, and inline quiz checks.',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        isPublished: true,
        isDownloadedOffline: true,
        slides: [
          SlideItem(
            id: 's1',
            slideIndex: 0,
            title: 'Welcome to Right Triangle Geometry',
            theme: 'midnightNeon',
            enableWhiteboard: true,
            blocks: [
              SlideBlock(
                id: 'b1',
                type: SlideBlockType.heading,
                content: 'The Pythagorean Theorem',
              ),
              SlideBlock(
                id: 'b2',
                type: SlideBlockType.paragraph,
                content: 'In mathematics, the Pythagorean theorem states that in a right-angled triangle, the area of the square whose side is the hypotenuse is equal to the sum of the areas of the squares on the other two sides.',
              ),
              SlideBlock(
                id: 'b3',
                type: SlideBlockType.callout,
                content: 'Key Formula: a² + b² = c² (where c is the hypotenuse)',
                extra: 'info',
              ),
              SlideBlock(
                id: 'b4',
                type: SlideBlockType.bulletList,
                content: 'Applicable ONLY to right-angled triangles (90°).\nForms the foundation of coordinate geometry & trigonometry.\nDiscovered independently by ancient Indian, Chinese, and Greek mathematicians.',
              ),
            ],
          ),
          SlideItem(
            id: 's2',
            slideIndex: 1,
            title: 'Interactive Math Proof & Computation',
            theme: 'darkGlass',
            enableWhiteboard: true,
            blocks: [
              SlideBlock(
                id: 'b5',
                type: SlideBlockType.subheading,
                content: 'Calculating Hypotenuse in Dart',
              ),
              SlideBlock(
                id: 'b6',
                type: SlideBlockType.paragraph,
                content: 'Below is how we compute the hypotenuse programmatically in Flutter/Dart using double precision math:',
              ),
              SlideBlock(
                id: 'b7',
                type: SlideBlockType.code,
                content: 'import "dart:math";\n\ndouble calculateHypotenuse(double a, double b) {\n  return sqrt(pow(a, 2) + pow(b, 2));\n}\n\nvoid main() {\n  print(calculateHypotenuse(3.0, 4.0)); // Output: 5.0\n}',
                extra: 'dart',
              ),
              SlideBlock(
                id: 'b8',
                type: SlideBlockType.callout,
                content: 'Pro-tip: Try tapping the Whiteboard Drawing button above to annotate right on top of this code snippet!',
                extra: 'tip',
              ),
            ],
          ),
          SlideItem(
            id: 's3',
            slideIndex: 2,
            title: 'Knowledge Check: Pythagorean Triples',
            theme: 'emeraldSlate',
            enableWhiteboard: true,
            quiz: SlideQuiz(
              question: 'Which of the following side length triplets forms a valid right-angled triangle?',
              options: ['3, 4, 6', '5, 12, 13', '6, 8, 11', '7, 9, 12'],
              correctIndex: 1,
              explanation: 'Because 5² + 12² = 25 + 144 = 169, and 13² = 169. This satisfies a² + b² = c²!',
            ),
            blocks: [
              SlideBlock(
                id: 'b9',
                type: SlideBlockType.heading,
                content: 'Quick Check Question',
              ),
              SlideBlock(
                id: 'b10',
                type: SlideBlockType.paragraph,
                content: 'Test your understanding before proceeding to coordinate geometry.',
              ),
            ],
          ),
        ],
      ),
    ];
  }
}
