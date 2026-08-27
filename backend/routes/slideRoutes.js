import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFile, exec } from 'child_process';
import { SlideDeck, SlideProgress } from '../models/SlideDeck.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const router = express.Router();

// Multer storage for PPTX file uploads
const pptxStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = path.join(__dirname, '../uploads/temp_pptx/');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '_' + Math.round(Math.random() * 1E6);
    const sanitized = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `${uniqueSuffix}_${sanitized}`);
  }
});
const uploadPptx = multer({
  storage: pptxStorage,
  limits: { fileSize: 100 * 1024 * 1024 } // 100MB limit
});

// POST /api/slide-decks/upload-pptx - Upload & convert a PPTX presentation into a SlideDeck
router.post('/upload-pptx', uploadPptx.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No .pptx file uploaded' });
    }

    const pptxPath = req.file.path;
    const courseName = req.body.courseName || 'Mathematics';
    const courseId = req.body.courseId || 'course_101';
    const theme = req.body.theme || 'darkGlass';
    const customTitle = req.body.title || path.parse(req.file.originalname).name.replace(/[_-]/g, ' ');

    const deckId = `deck_${Date.now()}`;
    const outputDir = path.join(__dirname, `../uploads/slides/${deckId}`);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Locate converter script
    const possibleScriptPaths = [
      path.resolve(__dirname, '../../convert_pptx_to_jyamiti.py'),
      path.resolve(process.cwd(), 'convert_pptx_to_jyamiti.py'),
      path.resolve(process.cwd(), '../convert_pptx_to_jyamiti.py'),
    ];
    let scriptPath = possibleScriptPaths.find(p => fs.existsSync(p));

    if (!scriptPath) {
      // Fallback: create temporary minimal converter invocation or check
      scriptPath = possibleScriptPaths[0];
    }

    const host = req.get('host');
    const protocol = req.protocol;
    const baseUrl = `${protocol}://${host}`;

    // Execute converter: python convert_pptx_to_jyamiti.py <pptxPath> -o <outputDir> -c <courseName> --theme <theme>
    const cmd = `python "${scriptPath}" "${pptxPath}" -o "${outputDir}" -c "${courseName}" --course-id "${courseId}" --theme "${theme}"`;

    exec(cmd, { timeout: 180000 }, async (error, stdout, stderr) => {
      // Remove temp PPTX upload
      try {
        if (fs.existsSync(pptxPath)) fs.unlinkSync(pptxPath);
      } catch (_) {}

      // Find generated json
      let jsonFile = null;
      if (fs.existsSync(outputDir)) {
        const files = fs.readdirSync(outputDir);
        const match = files.find(f => f.endsWith('_deck.json'));
        if (match) jsonFile = path.join(outputDir, match);
      }

      if (!jsonFile || !fs.existsSync(jsonFile)) {
        // If external conversion fails, return descriptive error
        return res.status(500).json({
          message: 'PPTX conversion failed. Ensure PowerPoint or Python is installed on server.',
          error: error ? error.message : stderr
        });
      }

      try {
        const rawContent = fs.readFileSync(jsonFile, 'utf-8');
        const deckData = JSON.parse(rawContent);
        deckData.id = deckId;
        deckData.title = customTitle;
        deckData.courseName = courseName;
        deckData.courseId = courseId;

        // Fix image URLs to point to static uploads endpoint: /uploads/slides/<deckId>/slide_<n>.png
        const slideImgDir = fs.readdirSync(outputDir).find(f => fs.statSync(path.join(outputDir, f)).isDirectory());
        
        if (slideImgDir && deckData.slides) {
          deckData.slides.forEach((slide, idx) => {
            const imgFileName = `slide_${idx + 1}.png`;
            const localImgPath = path.join(outputDir, slideImgDir, imgFileName);
            if (fs.existsSync(localImgPath)) {
              // Copy to root of deck directory for cleaner URL
              const targetPath = path.join(outputDir, imgFileName);
              if (!fs.existsSync(targetPath)) {
                fs.copyFileSync(localImgPath, targetPath);
              }
              slide.imageUrl = `${baseUrl}/uploads/slides/${deckId}/${imgFileName}`;
            }
          });
        }

        const savedDeck = await SlideDeck.findOneAndUpdate(
          { id: deckData.id },
          deckData,
          { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        res.status(201).json(savedDeck);
      } catch (parseErr) {
        res.status(500).json({ message: 'Failed to process converted slide deck JSON', error: parseErr.message });
      }
    });
  } catch (err) {
    res.status(500).json({ message: 'Error processing PPTX upload', error: err.message });
  }
});

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

// POST /api/slide-decks/import-deck - Import full slide deck JSON or array of decks
router.post('/import-deck', async (req, res) => {
  try {
    const payload = req.body;
    const decks = Array.isArray(payload) ? payload : [payload];
    const results = [];

    for (const deckData of decks) {
      if (!deckData.id) {
        deckData.id = `deck_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      }
      const updated = await SlideDeck.findOneAndUpdate(
        { id: deckData.id },
        deckData,
        { new: true, upsert: true, setDefaultsOnInsert: true }
      );
      results.push(updated);
    }

    res.status(201).json({ message: `Successfully imported ${results.length} deck(s)`, decks: results });
  } catch (error) {
    res.status(500).json({ message: 'Error importing slide deck(s)', error: error.message });
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
