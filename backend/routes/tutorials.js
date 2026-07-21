import express from 'express';
import { authenticateToken as authenticate, requireRole as authorizeRole } from '../middleware/authMiddleware.js';
import Tutorial from '../models/Tutorial.js';
import Batch from '../models/Batch.js';

const router = express.Router();

// POST /api/tutorials
// Tutor uploads a tutorial for a batch
router.post('/', authenticate, authorizeRole(['TUTOR']), async (req, res) => {
  try {
    const { batchId, title, videoUrl, sessionDate, chapter, description } = req.body;

    if (!batchId || !title || !videoUrl) {
      return res.status(400).json({ message: 'batchId, title, and videoUrl are required.' });
    }

    const batch = await Batch.findById(batchId);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    // Ensure the requesting tutor actually owns this batch
    if (batch.tutor.toString() !== req.user.id) {
      return res.status(403).json({ message: 'You are not the tutor for this batch' });
    }

    const tutorial = await Tutorial.create({
      batch: batchId,
      tutor: req.user.id,
      title,
      videoUrl,
      sessionDate: sessionDate || '',
      chapter: chapter || '',
      description: description || '',
    });

    res.status(201).json(tutorial);
  } catch (error) {
    console.error('Create tutorial error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/tutorials/batch/:batchId
// Get all tutorials for a batch (any authenticated user)
router.get('/batch/:batchId', authenticate, async (req, res) => {
  try {
    const tutorials = await Tutorial.find({ batch: req.params.batchId })
      .populate('tutor', 'name')
      .sort({ createdAt: -1 });
    res.json(tutorials);
  } catch (error) {
    console.error('Fetch tutorials error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/tutorials/:id
// Tutor deletes their own tutorial
router.delete('/:id', authenticate, authorizeRole(['TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const tutorial = await Tutorial.findById(req.params.id);
    if (!tutorial) return res.status(404).json({ message: 'Tutorial not found' });

    // Only the uploading tutor (or admin) can delete
    if (req.user.role !== 'ADMIN' && tutorial.tutor.toString() !== req.user.id) {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    await tutorial.deleteOne();
    res.json({ message: 'Tutorial deleted successfully' });
  } catch (error) {
    console.error('Delete tutorial error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
