import 'package:flutter/material.dart';
import '../../../../domain/models/slide_deck_models.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/slide_cache_service.dart';
import 'admin_slide_analytics_screen.dart';
import 'admin_slide_cms_screen.dart';
import 'student_slide_viewer_screen.dart';

class SlideDecksManagerScreen extends StatefulWidget {
  final bool isAdmin;

  const SlideDecksManagerScreen({super.key, this.isAdmin = false});

  @override
  State<SlideDecksManagerScreen> createState() =>
      _SlideDecksManagerScreenState();
}

class _SlideDecksManagerScreenState extends State<SlideDecksManagerScreen> {
  List<SlideDeck> _decks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  Future<void> _loadDecks() async {
    final decks = await SlideCacheService.instance.getSlideDecks();
    setState(() {
      _decks = decks;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAdmin ? 'Slide Decks CMS & Analytics' : 'Course Slide Decks',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadDecks,
            tooltip: 'Refresh',
          ),
          if (widget.isAdmin)
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminSlideCmsScreen(),
                  ),
                );
                _loadDecks();
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create New Deck'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _decks.isEmpty
          ? _buildEmptyState(isDark)
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _decks.length,
              itemBuilder: (context, idx) {
                final deck = _decks[idx];
                return _buildDeckCard(context, deck, isDark);
              },
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.slideshow_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No Slide Decks Available Yet',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create slide decks using the Admin CMS above to start teaching.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDeckCard(BuildContext context, SlideDeck deck, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    deck.courseName.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Spacer(),
                if (deck.isDownloadedOffline)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.offline_pin_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Downloaded',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              deck.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              deck.description,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.layers_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  '${deck.slides.length} Slides',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),

                // Action Buttons
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentSlideViewerScreen(deck: deck),
                      ),
                    );
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Open Slides'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                  ),
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.analytics_outlined,
                      color: Color(0xFF0EA5E9),
                    ),
                    tooltip: 'Analytics',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminSlideAnalyticsScreen(deck: deck),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.amber),
                    tooltip: 'Edit CMS',
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdminSlideCmsScreen(initialDeck: deck),
                        ),
                      );
                      _loadDecks();
                    },
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Delete Deck',
                    onPressed: () async {
                      await SlideCacheService.instance.deleteDeck(deck.id);
                      _loadDecks();
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
