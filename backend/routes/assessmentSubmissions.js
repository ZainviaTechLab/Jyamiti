import express from 'express';
import AssessmentSubmission from '../models/AssessmentSubmission.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

// GET /check-phone/:number - Check if a phone number already exists (Public)
router.get('/check-phone/:number', async (req, res) => {
  try {
    const number = req.params.number.trim();
    const submission = await AssessmentSubmission.findOne({ whatsappNumber: number });
    res.json({ taken: !!submission });
  } catch (error) {
    console.error('Check phone number error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /submit - Submit test results (Public)
router.post('/submit', async (req, res) => {
  try {
    const { name, whatsappNumber, grade, score, totalQuestions, answers } = req.body;

    if (!name || !whatsappNumber || grade === undefined || score === undefined || totalQuestions === undefined) {
      return res.status(400).json({ message: 'All fields (name, whatsappNumber, grade, score, totalQuestions) are required.' });
    }

    const number = whatsappNumber.trim();
    // Check if the number has already taken the test
    const existing = await AssessmentSubmission.findOne({ whatsappNumber: number });
    if (existing) {
      return res.status(400).json({ message: 'you already taken the test' });
    }

    const submission = await AssessmentSubmission.create({
      name,
      whatsappNumber: number,
      grade,
      score,
      totalQuestions,
      answers: answers || []
    });

    res.status(201).json(submission);
  } catch (error) {
    console.error('Submit assessment results error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET / - Get all submissions (Admin/Tutor only)
router.get('/', authenticateToken, requireRole(['ADMIN', 'TUTOR']), async (req, res) => {
  try {
    const submissions = await AssessmentSubmission.find().sort({ createdAt: -1 });
    res.json(submissions);
  } catch (error) {
    console.error('Fetch submissions error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
