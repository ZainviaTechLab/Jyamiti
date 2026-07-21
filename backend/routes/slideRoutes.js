import express from 'express';
import { SlideDeck, SlideProgress } from '../models/SlideDeck.js';

const router = express.Router();

// GET /api/slide-decks - Get all slide decks
router.get('/', async (req, res) => {
  try {
    const decks = await SlideDeck.find().sort({ updatedAt: -1 });
    res.json(decks);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching slide decks', error: error.message });
  }
});

// GET /api/slide-decks/:id - Get single slide deck
router.get('/:id', async (req, res) => {
  try {
    const deck = await SlideDeck.findOne({ id: req.params.id });
    if (!deck) {
      return res.status(404).json({ message: 'Slide deck not found' });
    }
    res.json(deck);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching slide deck', error: error.message });
  }
});

// POST /api/slide-decks - Create or update slide deck
router.post('/', async (req, res) => {
  try {
    const deckData = req.body;
    if (!deckData.id) {
      deckData.id = `deck_${Date.now()}`;
    }

    const updatedDeck = await SlideDeck.findOneAndUpdate(
      { id: deckData.id },
      deckData,
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );

    res.status(200).json(updatedDeck);
  } catch (error) {
    res.status(500).json({ message: 'Error saving slide deck', error: error.message });
  }
});

// DELETE /api/slide-decks/:id - Delete slide deck
router.delete('/:id', async (req, res) => {
  try {
    await SlideDeck.findOneAndDelete({ id: req.params.id });
    await SlideProgress.deleteMany({ deckId: req.params.id });
    res.json({ message: 'Slide deck deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting slide deck', error: error.message });
  }
});

// POST /api/slide-decks/:id/progress - Save student progress
router.post('/:id/progress', async (req, res) => {
  try {
    const deckId = req.params.id;
    const progressData = req.body;
    progressData.deckId = deckId;

    const progress = await SlideProgress.findOneAndUpdate(
      { deckId, userId: progressData.userId || 'stu_current' },
      progressData,
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );

    res.json(progress);
  } catch (error) {
    res.status(500).json({ message: 'Error saving slide progress', error: error.message });
  }
});

// GET /api/slide-decks/:id/progress - Get student progress
router.get('/:id/progress', async (req, res) => {
  try {
    const deckId = req.params.id;
    const progress = await SlideProgress.findOne({
      deckId,
      userId: req.query.userId || 'stu_current',
    });
    res.json(progress || { deckId, timeSpentPerSlide: {}, completedSlides: {}, bookmarkedSlides: {}, quizAnswers: {}, slideDrawings: {} });
  } catch (error) {
    res.status(500).json({ message: 'Error loading slide progress', error: error.message });
  }
});

export default router;
