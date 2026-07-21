import express from 'express';
import BatchCategory from '../models/BatchCategory.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

// GET /api/batch-categories
router.get('/', authenticateToken, async (req, res) => {
  try {
    const categories = await BatchCategory.find().sort({ createdAt: -1 });
    res.json(categories.map(c => ({
      id: c._id,
      name: c.name,
      maxMembers: c.maxMembers,
      fees: c.fees,
      createdAt: c.createdAt
    })));
  } catch (error) {
    console.error('Fetch batch categories error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/batch-categories
router.post('/', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { name, maxMembers, fees } = req.body;
  if (!name || maxMembers == null || fees == null) {
    return res.status(400).json({ message: 'Name, maxMembers, and fees are required' });
  }

  try {
    const existing = await BatchCategory.findOne({ name });
    if (existing) {
      return res.status(400).json({ message: 'Batch category with this name already exists' });
    }

    const category = await BatchCategory.create({ name, maxMembers, fees });
    res.status(201).json({
      id: category._id,
      name: category.name,
      maxMembers: category.maxMembers,
      fees: category.fees,
      createdAt: category.createdAt
    });
  } catch (error) {
    console.error('Create batch category error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/batch-categories/:id
router.put('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { name, maxMembers, fees } = req.body;
  try {
    const category = await BatchCategory.findById(req.params.id);
    if (!category) return res.status(404).json({ message: 'Batch category not found' });

    if (name) category.name = name;
    if (maxMembers != null) category.maxMembers = maxMembers;
    if (fees != null) category.fees = fees;

    await category.save();
    res.json({
      id: category._id,
      name: category.name,
      maxMembers: category.maxMembers,
      fees: category.fees,
      createdAt: category.createdAt
    });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(400).json({ message: 'Batch category with this name already exists' });
    }
    console.error('Update batch category error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/batch-categories/:id
router.delete('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  try {
    const category = await BatchCategory.findByIdAndDelete(req.params.id);
    if (!category) return res.status(404).json({ message: 'Batch category not found' });
    res.json({ message: 'Batch category deleted successfully' });
  } catch (error) {
    console.error('Delete batch category error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
