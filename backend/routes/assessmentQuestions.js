import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import AssessmentQuestion from '../models/AssessmentQuestion.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

const uploadDir = 'uploads/';
if (!fs.existsSync(uploadDir)){
    fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    cb(null, 'assessment_' + Date.now() + path.extname(file.originalname));
  }
});

const upload = multer({ 
  storage: storage,
  fileFilter: (req, file, cb) => {
    // Allow images and SVGs
    const filetypes = /jpeg|jpg|png|gif|svg|svg\+xml/;
    const mimetype = filetypes.test(file.mimetype);
    const extname = filetypes.test(path.extname(file.originalname).toLowerCase());

    if (mimetype || extname) {
      return cb(null, true);
    }
    cb(new Error('Only image and SVG files are allowed!'));
  }
});

// GET / - Get all assessment questions with optional grade filter
router.get('/', authenticateToken, requireRole(['ADMIN', 'TUTOR']), async (req, res) => {
  try {
    const { grade } = req.query;
    const filter = {};
    if (grade) {
      const gradeNum = parseInt(grade, 10);
      if (!isNaN(gradeNum)) {
        filter.grade = gradeNum;
      }
    }
    const questions = await AssessmentQuestion.find(filter).sort({ createdAt: -1 });
    res.json(questions);
  } catch (error) {
    console.error('Fetch all assessment questions error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /grade/:grade - Get questions for a grade (Public access for taking tests)
router.get('/grade/:grade', async (req, res) => {
  try {
    const gradeNum = parseInt(req.params.grade);
    if (isNaN(gradeNum)) {
      return res.status(400).json({ message: 'Invalid grade number' });
    }
    const questions = await AssessmentQuestion.aggregate([
      { $match: { grade: gradeNum } },
      { $sample: { size: 30 } }
    ]);
    res.json(questions);
  } catch (error) {
    console.error('Fetch assessment questions error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /:id - Get a single question by ID
router.get('/:id', async (req, res) => {
  try {
    const question = await AssessmentQuestion.findById(req.params.id);
    if (!question) {
      return res.status(404).json({ message: 'Assessment question not found' });
    }
    res.json(question);
  } catch (error) {
    console.error('Fetch single assessment question error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /upload - Upload a file (SVG, image)
router.post('/upload', authenticateToken, requireRole(['ADMIN', 'TUTOR']), upload.single('file'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }
    const fileUrl = req.file.path.replace(/\\/g, '/');
    res.status(200).json({ fileUrl });
  } catch (error) {
    console.error('Upload assessment file error:', error);
    res.status(500).json({ message: 'Internal server error during file upload' });
  }
});

// POST / - Create a new question
router.post('/', authenticateToken, requireRole(['ADMIN', 'TUTOR']), async (req, res) => {
  try {
    const { grade, type, descriptiveText, text, isSvg, questionImage, options, rightOptions, geometryNodes, geometryLinesCount, hideGeometryNodes, correctAnswers, marks, shortAnswerPrefix, shortAnswerSuffix, shortAnswerHint, svgLabels, explanation, explanationSteps, isClasswork, category, tag } = req.body;

    if (!grade || !type || !text) {
      return res.status(400).json({ message: 'Grade, type, and text are required fields.' });
    }

    const question = await AssessmentQuestion.create({
      grade,
      type,
      descriptiveText: descriptiveText || '',
      text,
      isSvg: isSvg === true,
      questionImage: questionImage || '',
      options: options || [],
      rightOptions: rightOptions || [],
      geometryNodes: geometryNodes || [],
      geometryLinesCount: geometryLinesCount || 1,
      hideGeometryNodes: hideGeometryNodes === true,
      correctAnswers: correctAnswers || [],
      marks: marks || 1,
      shortAnswerPrefix: shortAnswerPrefix || '',
      shortAnswerSuffix: shortAnswerSuffix || '',
      shortAnswerHint: shortAnswerHint || '',
      svgLabels: svgLabels || [],
      explanation: explanation || '',
      explanationSteps: explanationSteps || [],
      isClasswork: isClasswork === true || isClasswork === 'true',
      category: category || (isClasswork ? 'classwork' : 'practice'),
      tag: tag || ''
    });

    res.status(201).json(question);
  } catch (error) {
    console.error('Create assessment question error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /:id - Edit an existing question
router.put('/:id', authenticateToken, requireRole(['ADMIN', 'TUTOR']), async (req, res) => {
  try {
    const { grade, type, descriptiveText, text, isSvg, questionImage, options, rightOptions, geometryNodes, geometryLinesCount, hideGeometryNodes, correctAnswers, marks, shortAnswerPrefix, shortAnswerSuffix, shortAnswerHint, svgLabels, explanation, explanationSteps, isClasswork, category, tag } = req.body;

    const question = await AssessmentQuestion.findByIdAndUpdate(
      req.params.id,
      {
        grade, type, descriptiveText, text, isSvg, questionImage, options, rightOptions, geometryNodes, geometryLinesCount, hideGeometryNodes, correctAnswers, marks, shortAnswerPrefix, shortAnswerSuffix, shortAnswerHint, svgLabels,
        explanation: explanation || '',
        explanationSteps: explanationSteps || [],
        isClasswork: isClasswork === true || isClasswork === 'true',
        category: category || (isClasswork ? 'classwork' : 'practice'),
        tag: tag || ''
      },
      { new: true }
    );

    if (!question) {
      return res.status(404).json({ message: 'Assessment question not found' });
    }

    res.status(200).json(question);
  } catch (error) {
    console.error('Update assessment question error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /:id - Delete a question
router.delete('/:id', authenticateToken, requireRole(['ADMIN', 'TUTOR']), async (req, res) => {
  try {
    const question = await AssessmentQuestion.findByIdAndDelete(req.params.id);
    if (!question) {
      return res.status(404).json({ message: 'Assessment question not found' });
    }
    res.status(200).json({ message: 'Assessment question deleted successfully' });
  } catch (error) {
    console.error('Delete assessment question error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
