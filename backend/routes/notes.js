import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import Note from '../models/Note.js';
import NoteSubmission from '../models/NoteSubmission.js';
import Batch from '../models/Batch.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

const uploadDir = 'uploads/';
if (!fs.existsSync(uploadDir)){
    fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir)
  },
  filename: function (req, file, cb) {
    cb(null, 'note_' + Date.now() + path.extname(file.originalname))
  }
});
const upload = multer({ storage: storage });

// POST /api/notes
router.post('/', authenticateToken, requireRole(['TUTOR']), upload.single('file'), async (req, res) => {
  try {
    const { title, description, batchId, sessionDate, isDownloadable } = req.body;
    const batch = await Batch.findById(batchId);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });
    
    if (batch.tutor.toString() !== req.user.id) {
      return res.status(403).json({ message: 'You are not the tutor for this batch' });
    }

    const criteria = ['Completed on time', 'Missing content', 'Neatness', 'No correction'];
    const fileUrl = req.file ? req.file.path.replace(/\\/g, '/') : null;

    const note = await Note.create({
      title, description, batch: batchId, tutor: req.user.id, sessionDate, criteria, fileUrl,
      isDownloadable: isDownloadable === 'true'
    });
    res.status(201).json(note);
  } catch (error) {
    console.error('Create note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/notes/:id
router.put('/:id', authenticateToken, requireRole(['TUTOR', 'ADMIN']), upload.single('file'), async (req, res) => {
  try {
    const { title, description, isDownloadable } = req.body;
    const note = await Note.findById(req.params.id);
    
    if (!note) return res.status(404).json({ message: 'Note not found' });
    
    if (note.tutor.toString() !== req.user.id && req.user.role !== 'ADMIN') {
      return res.status(403).json({ message: 'You are not authorized to edit this note' });
    }

    note.title = title || note.title;
    note.description = description || note.description;
    if (isDownloadable !== undefined) {
      note.isDownloadable = isDownloadable === 'true';
    }
    
    if (req.file) {
      note.fileUrl = req.file.path.replace(/\\/g, '/');
    }

    await note.save();
    res.status(200).json(note);
  } catch (error) {
    console.error('Edit note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/notes/batch/:batchId
router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const notes = await Note.find({ batch: req.params.batchId }).sort({ createdAt: -1 });
    res.json(notes);
  } catch (error) {
    console.error('Fetch notes error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/notes/batch/:batchId/all
router.get('/batch/:batchId/all', authenticateToken, async (req, res) => {
  try {
    const teacherNotes = await Note.find({ batch: req.params.batchId });
    
    let studentSubmissions = [];
    if (req.user.role === 'STUDENT') {
      studentSubmissions = await NoteSubmission.find({ batch: req.params.batchId, student: req.user.id }).populate('student', 'name email');
    } else {
      studentSubmissions = await NoteSubmission.find({ batch: req.params.batchId }).populate('student', 'name email');
    }
    
    res.json({ teacherNotes, studentSubmissions });
  } catch (error) {
    console.error('Fetch all batch notes error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/notes/student-upload
router.post('/student-upload', authenticateToken, requireRole(['STUDENT']), upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'Please upload a file' });
    }
    const { title, description, batchId, sessionDate } = req.body;
    
    let submission = await NoteSubmission.findOne({ batch: batchId, sessionDate: new Date(sessionDate), student: req.user.id });
    if (submission) {
      submission.fileUrl = req.file.path.replace(/\\/g, '/');
      submission.title = title;
      submission.description = description;
      submission.status = 'SUBMITTED';
      await submission.save();
    } else {
      submission = await NoteSubmission.create({
        batch: batchId,
        sessionDate: new Date(sessionDate),
        title,
        description,
        student: req.user.id,
        fileUrl: req.file.path.replace(/\\/g, '/')
      });
    }
    res.status(200).json(submission);
  } catch (error) {
    console.error('Submit student note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/notes/submissions/:submissionId
router.put('/submissions/:submissionId', authenticateToken, requireRole(['STUDENT']), upload.single('file'), async (req, res) => {
  try {
    const { title, description } = req.body;
    const submission = await NoteSubmission.findById(req.params.submissionId);
    
    if (!submission) return res.status(404).json({ message: 'Submission not found' });
    
    if (submission.student.toString() !== req.user.id) {
      return res.status(403).json({ message: 'You are not authorized to edit this submission' });
    }

    submission.title = title || submission.title;
    submission.description = description || submission.description;
    submission.status = 'SUBMITTED'; // Reset status if edited
    
    if (req.file) {
      submission.fileUrl = req.file.path.replace(/\\/g, '/');
    }

    await submission.save();
    res.status(200).json(submission);
  } catch (error) {
    console.error('Edit student note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});


// GET /api/notes/:id/submissions
router.get('/:id/submissions', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const submissions = await NoteSubmission.find({ note: req.params.id })
      .populate('student', 'name email');
    res.json(submissions);
  } catch (error) {
    console.error('Fetch note submissions error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/notes/:id/my-submission
router.get('/:id/my-submission', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const submission = await NoteSubmission.findOne({ note: req.params.id, student: req.user.id });
    res.json(submission || null);
  } catch (error) {
    console.error('Fetch my note submission error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/notes/:id/submit
router.post('/:id/submit', authenticateToken, requireRole(['STUDENT']), upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'Please upload a file' });
    }
    const note = await Note.findById(req.params.id);
    if (!note) return res.status(404).json({ message: 'Note not found' });
    
    let submission = await NoteSubmission.findOne({ note: req.params.id, student: req.user.id });
    if (submission) {
      submission.fileUrl = req.file.path.replace(/\\/g, '/');
      submission.status = 'SUBMITTED';
      await submission.save();
    } else {
      submission = await NoteSubmission.create({
        note: req.params.id,
        student: req.user.id,
        fileUrl: req.file.path.replace(/\\/g, '/')
      });
    }
    res.status(200).json(submission);
  } catch (error) {
    console.error('Submit note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/notes/submissions/:submissionId/review
router.put('/submissions/:submissionId/review', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { criteriaValues } = req.body;
    const submission = await NoteSubmission.findById(req.params.submissionId);
    if (!submission) return res.status(404).json({ message: 'Submission not found' });

    submission.criteriaValues = criteriaValues;
    submission.status = 'REVIEWED';
    
    await submission.save();
    res.json(submission);
  } catch (error) {
    console.error('Review note error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
