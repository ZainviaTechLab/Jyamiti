import express from 'express';
import Question from '../models/Question.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

router.get('/course/:courseId', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const questions = await Question.find({ course: req.params.courseId }).sort({ createdAt: -1 });
    res.json(questions);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.post('/', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { course, chapter, topic, type, text, options, correctAnswers, marks } = req.body;
    const question = await Question.create({ course, chapter, topic, type, text, options, correctAnswers, marks });
    res.status(201).json(question);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.post('/bulk', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { questions } = req.body;
    if (!Array.isArray(questions)) {
      return res.status(400).json({ message: 'Invalid data format. Expected an array of questions.' });
    }
    const insertedQuestions = await Question.insertMany(questions);
    res.status(201).json({ message: `${insertedQuestions.length} questions added successfully.`, insertedQuestions });
  } catch (error) {
    console.error('Error inserting bulk questions:', error);
    res.status(500).json({ message: 'Internal server error during bulk insert.' });
  }
});

router.put('/:id', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { course, chapter, topic, type, text, options, correctAnswers, marks } = req.body;
    const question = await Question.findByIdAndUpdate(
      req.params.id,
      { course, chapter, topic, type, text, options, correctAnswers, marks },
      { new: true }
    );
    if (!question) return res.status(404).json({ message: 'Question not found' });
    res.status(200).json(question);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.delete('/:id', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  try {
    await Question.findByIdAndDelete(req.params.id);
    res.status(200).json({ message: 'Question deleted' });
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
