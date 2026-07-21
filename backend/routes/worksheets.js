import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import Worksheet from '../models/Worksheet.js';
import WorksheetSubmission from '../models/WorksheetSubmission.js';
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
    cb(null, Date.now() + path.extname(file.originalname))
  }
});
const upload = multer({ storage: storage });

// POST /api/Worksheets
router.post('/', authenticateToken, requireRole(['TUTOR']), upload.single('file'), async (req, res) => {
  try {
    const { title, description, batchId, dueDate, maxScore, isDownloadable, sessionDate } = req.body;
    const batch = await Batch.findById(batchId);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });
    
    if (batch.tutor.toString() !== req.user.id) {
      return res.status(403).json({ message: 'You are not the tutor for this batch' });
    }

    const fileUrl = req.file ? req.file.path.replace(/\\/g, '/') : null;

    const Worksheet = await Worksheet.create({
      title, description, batch: batchId, tutor: req.user.id, dueDate, maxScore, fileUrl,
      isDownloadable: isDownloadable === 'true',
      sessionDate
    });
    res.status(201).json(Worksheet);
  } catch (error) {
    console.error('Create Worksheet error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/Worksheets/:id
router.put('/:id', authenticateToken, requireRole(['TUTOR']), upload.single('file'), async (req, res) => {
  try {
    const { title, description, dueDate, maxScore, isDownloadable, sessionDate } = req.body;
    let Worksheet = await Worksheet.findById(req.params.id);
    if (!Worksheet) return res.status(404).json({ message: 'Worksheet not found' });
    
    if (Worksheet.tutor.toString() !== req.user.id) {
      return res.status(403).json({ message: 'You are not the tutor for this Worksheet' });
    }

    Worksheet.title = title || Worksheet.title;
    Worksheet.description = description || Worksheet.description;
    Worksheet.dueDate = dueDate || Worksheet.dueDate;
    Worksheet.maxScore = maxScore || Worksheet.maxScore;
    
    if (sessionDate) {
      Worksheet.sessionDate = sessionDate;
    }
    
    if (isDownloadable !== undefined) {
      Worksheet.isDownloadable = isDownloadable === 'true';
    }
    
    if (req.file) {
      Worksheet.fileUrl = req.file.path.replace(/\\/g, '/');
    }

    await Worksheet.save();
    res.status(200).json(Worksheet);
  } catch (error) {
    console.error('Update Worksheet error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/Worksheets/batch/:batchId
router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const Worksheets = await Worksheet.find({ batch: req.params.batchId }).sort({ createdAt: -1 });
    res.json(Worksheets);
  } catch (error) {
    console.error('Fetch Worksheets error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/Worksheets/:id/submissions
router.get('/:id/submissions', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const submissions = await WorksheetSubmission.find({ Worksheet: req.params.id })
      .populate('student', 'name email');
    res.json(submissions);
  } catch (error) {
    console.error('Fetch submissions error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/Worksheets/:id/my-submission
router.get('/:id/my-submission', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const submission = await WorksheetSubmission.findOne({ Worksheet: req.params.id, student: req.user.id });
    res.json(submission || null);
  } catch (error) {
    console.error('Fetch my submission error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/Worksheets/:id/submit
router.post('/:id/submit', authenticateToken, requireRole(['STUDENT']), upload.single('pdf'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'Please upload a PDF file' });
    }
    const Worksheet = await Worksheet.findById(req.params.id);
    if (!Worksheet) return res.status(404).json({ message: 'Worksheet not found' });
    
    let submission = await WorksheetSubmission.findOne({ Worksheet: req.params.id, student: req.user.id });
    if (submission) {
      submission.fileUrl = req.file.path.replace(/\\/g, '/');
      submission.status = 'SUBMITTED';
      await submission.save();
    } else {
      submission = await WorksheetSubmission.create({
        Worksheet: req.params.id,
        student: req.user.id,
        fileUrl: req.file.path.replace(/\\/g, '/')
      });
    }
    res.status(200).json(submission);
  } catch (error) {
    console.error('Submit Worksheet error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/Worksheets/:id/submissions/:submissionId/grade
router.put('/:id/submissions/:submissionId/grade', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { totalScore, remark } = req.body;
    const submission = await WorksheetSubmission.findById(req.params.submissionId);
    if (!submission) return res.status(404).json({ message: 'Submission not found' });

    submission.totalScore = totalScore;
    submission.remark = remark;
    submission.status = 'GRADED';
    
    await submission.save();
    res.json(submission);
  } catch (error) {
    console.error('Grade Worksheet error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/Worksheets/:id/submissions/:submissionId/annotate
router.post('/:id/submissions/:submissionId/annotate', authenticateToken, requireRole(['TUTOR', 'MENTOR']), upload.single('pdf'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'Please upload an annotated PDF file' });
    }
    const submission = await WorksheetSubmission.findById(req.params.submissionId);
    if (!submission) return res.status(404).json({ message: 'Submission not found' });

    submission.annotatedFileUrl = req.file.path.replace(/\\/g, '/');
    await submission.save();
    
    res.status(200).json(submission);
  } catch (error) {
    console.error('Annotate Worksheet error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;

