import express from 'express';
import Assignment from '../models/Assignment.js';
import User from '../models/User.js';
import Batch from '../models/Batch.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

// Get assignments for a student
router.get('/student/:studentId', authenticateToken, async (req, res) => {
  try {
    const student = await User.findById(req.params.studentId);
    if (!student) {
      return res.status(404).json({ message: 'Student not found' });
    }
    
    // Student can only see their own assignments, or admin/tutor can see them
    if (req.user.role.toUpperCase() === 'STUDENT' && req.user.id !== req.params.studentId) {
      return res.status(403).json({ message: 'Access denied' });
    }

    const batches = await Batch.find({ students: student._id });
    const batchIds = batches.map(b => b._id);

    // Find assignments specific to the student OR assigned to their batches (where student is null)
    const assignments = await Assignment.find({
      $or: [
        { student: student._id },
        { batch: { $in: batchIds }, student: null }
      ]
    }).populate('tutor', 'name').populate('batch', 'name').sort({ dueDate: 1 });

    res.json(assignments);
  } catch (error) {
    console.error('Error fetching assignments:', error);
    res.status(500).json({ message: 'Server error fetching assignments' });
  }
});

// Get assignments for a batch
router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const assignments = await Assignment.find({ batch: req.params.batchId })
      .populate('tutor', 'name')
      .populate('student', 'name')
      .sort({ dueDate: 1 });
    res.json(assignments);
  } catch (error) {
    console.error('Error fetching batch assignments:', error);
    res.status(500).json({ message: 'Server error fetching assignments' });
  }
});

// Create assignment (Tutor/Admin only)
router.post('/', authenticateToken, requireRole(['tutor', 'admin', 'TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const { batch, student, itemType, itemTitle, itemData, dueDate } = req.body;

    if (!batch || !itemType || !itemTitle || !dueDate) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    if (student) {
      // Assign to a specific student
      const newAssignment = new Assignment({
        tutor: req.user.id,
        batch,
        student,
        itemType,
        itemTitle,
        itemData,
        dueDate
      });
      const savedAssignment = await newAssignment.save();
      return res.status(201).json(savedAssignment);
    } else {
      // Assign to the whole batch - create a copy for each enrolled student
      const batchDoc = await Batch.findById(batch);
      if (!batchDoc) {
        return res.status(404).json({ message: 'Batch not found' });
      }

      const studentIds = batchDoc.students || [];
      if (studentIds.length === 0) {
        // Fallback to a single assignment with student: null if no students in batch yet
        const newAssignment = new Assignment({
          tutor: req.user.id,
          batch,
          student: null,
          itemType,
          itemTitle,
          itemData,
          dueDate
        });
        const savedAssignment = await newAssignment.save();
        return res.status(201).json(savedAssignment);
      }

      const assignmentsToCreate = studentIds.map(sId => ({
        tutor: req.user.id,
        batch,
        student: sId,
        itemType,
        itemTitle,
        itemData,
        dueDate
      }));

      const savedAssignments = await Assignment.insertMany(assignmentsToCreate);
      return res.status(201).json(savedAssignments[0]);
    }
  } catch (error) {
    console.error('Error creating assignment:', error);
    res.status(500).json({ message: 'Server error creating assignment' });
  }
});

// Get assignments created by the authenticated tutor
router.get('/tutor', authenticateToken, requireRole(['tutor', 'admin', 'TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const assignments = await Assignment.find({ tutor: req.user.id })
      .populate('student', 'name email')
      .populate('batch', 'name')
      .sort({ createdAt: -1 });
    res.json(assignments);
  } catch (error) {
    console.error('Error fetching tutor assignments:', error);
    res.status(500).json({ message: 'Server error fetching tutor assignments' });
  }
});

// Update assignment due date (Tutor/Admin only)
router.put('/:id', authenticateToken, requireRole(['tutor', 'admin', 'TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const { dueDate, status } = req.body;

    const assignment = await Assignment.findById(req.params.id);
    if (!assignment) {
      return res.status(404).json({ message: 'Assignment not found' });
    }

    if (dueDate) assignment.dueDate = dueDate;
    if (status) assignment.status = status;

    const updated = await assignment.save();
    res.json(updated);
  } catch (error) {
    console.error('Error updating assignment:', error);
    res.status(500).json({ message: 'Server error updating assignment' });
  }
});

// Mark assignment as completed (Student — marks their own assignment done)
router.patch('/:id/complete', authenticateToken, async (req, res) => {
  try {
    const assignment = await Assignment.findById(req.params.id);
    if (!assignment) {
      return res.status(404).json({ message: 'Assignment not found' });
    }

    // Allow only the assigned student, or tutor/admin
    const role = req.user.role.toUpperCase();
    const isOwner = assignment.student?.toString() === req.user.id ||
                    assignment.batch !== null; // batch-level assignments can be completed by any enrolled student
    const isStaff = role === 'TUTOR' || role === 'ADMIN';

    if (!isOwner && !isStaff) {
      return res.status(403).json({ message: 'Access denied' });
    }

    assignment.status = 'completed';
    if (req.body.score !== undefined && req.body.score !== null) {
      assignment.score = req.body.score;
    }
    if (req.body.totalQuestions !== undefined && req.body.totalQuestions !== null) {
      assignment.totalQuestions = req.body.totalQuestions;
    }

    const updated = await assignment.save();
    res.json(updated);
  } catch (error) {
    console.error('Error completing assignment:', error);
    res.status(500).json({ message: 'Server error completing assignment' });
  }
});

// Get performances (enrolled students & all assignments) for a batch
router.get('/batch/:batchId/performances', authenticateToken, requireRole(['tutor', 'admin', 'TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const batch = await Batch.findById(req.params.batchId).populate('students', 'name email');
    if (!batch) {
      return res.status(404).json({ message: 'Batch not found' });
    }

    const assignments = await Assignment.find({ batch: batch._id });

    res.json({
      students: batch.students || [],
      assignments: assignments || []
    });
  } catch (error) {
    console.error('Error fetching batch performances:', error);
    res.status(500).json({ message: 'Server error fetching performances' });
  }
});

// Delete assignment
router.delete('/:id', authenticateToken, requireRole(['tutor', 'admin', 'TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const assignment = await Assignment.findOneAndDelete({ _id: req.params.id, tutor: req.user.id });
    if (!assignment) {
      return res.status(404).json({ message: 'Assignment not found or unauthorized' });
    }
    res.json({ message: 'Assignment deleted successfully' });
  } catch (error) {
    console.error('Error deleting assignment:', error);
    res.status(500).json({ message: 'Server error deleting assignment' });
  }
});

export default router;
