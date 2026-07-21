import express from 'express';
import Course from '../models/Course.js';
import Batch from '../models/Batch.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

// GET /api/courses
router.get('/', authenticateToken, async (req, res) => {
  try {
    const courses = await Course.find().sort({ name: 1 });
    const result = await Promise.all(courses.map(async (c) => {
      const batchCount = await Batch.countDocuments({ course: c._id });
      return { 
        id: c._id, 
        name: c.name, 
        description: c.description, 
        grade: c.grade, 
        subject: c.subject, 
        syllabus: c.syllabus, 
        batchCount, 
        createdAt: c.createdAt 
      };
    }));
    res.json(result);
  } catch (error) {
    console.error('Fetch courses error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/courses
router.post('/', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { name, description, grade, subject, syllabus } = req.body;
  if (!name) return res.status(400).json({ message: 'Course name is required' });
  try {
    const existing = await Course.findOne({ name });
    if (existing) return res.status(400).json({ message: 'Course name already exists' });

    const course = await Course.create({ name, description, grade, subject, syllabus });
    res.status(201).json({ 
      id: course._id, 
      name: course.name, 
      description: course.description, 
      grade: course.grade, 
      subject: course.subject, 
      syllabus: course.syllabus 
    });
  } catch (error) {
    console.error('Create course error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/courses/:id
router.put('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { id } = req.params;
  const { name, description, grade, subject, syllabus } = req.body;
  try {
    const course = await Course.findById(id);
    if (!course) return res.status(404).json({ message: 'Course not found' });

    if (name && name !== course.name) {
      const existing = await Course.findOne({ name });
      if (existing) return res.status(400).json({ message: 'Course name already exists' });
    }

    course.name = name || course.name;
    course.description = description !== undefined ? description : course.description;
    if (grade !== undefined) course.grade = grade;
    if (subject !== undefined) course.subject = subject;
    if (syllabus !== undefined) course.syllabus = syllabus;
    
    await course.save();

    res.json({ 
      id: course._id, 
      name: course.name, 
      description: course.description, 
      grade: course.grade, 
      subject: course.subject, 
      syllabus: course.syllabus 
    });
  } catch (error) {
    console.error('Update course error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/courses/:id
router.delete('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { id } = req.params;
  try {
    const course = await Course.findById(id);
    if (!course) return res.status(404).json({ message: 'Course not found' });

    // Delete associated batches
    await Batch.deleteMany({ course: id });
    await Course.findByIdAndDelete(id);

    res.json({ message: 'Course and its batches deleted successfully' });
  } catch (error) {
    console.error('Delete course error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/courses/:id
router.get('/:id', authenticateToken, async (req, res) => {
  const { id } = req.params;
  try {
    const course = await Course.findById(id);
    if (!course) return res.status(404).json({ message: 'Course not found' });
    res.json(course);
  } catch (error) {
    console.error('Fetch course details error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
