import express from 'express';
import Batch from '../models/Batch.js';
import User from '../models/User.js';
import Course from '../models/Course.js';
import BatchCategory from '../models/BatchCategory.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';
import { hasScheduleConflict } from '../services/timeUtils.js';
import { generateSchedules } from '../services/scheduleGenerator.js';

const router = express.Router();

const populateFields = [
  { path: 'category', select: 'name maxMembers fees' },
  { path: 'course', select: 'name description' },
  { path: 'tutor', select: 'name email' },
  { path: 'mentors', select: 'name email' },
  { path: 'students', select: 'name email' },
];

function formatBatch(b) {
  return {
    id: b._id,
    name: b.name,
    category: b.category,
    course: b.course,
    tutor: b.tutor,
    mentors: b.mentors,
    students: b.students,
    daysOfWeek: b.daysOfWeek,
    timePeriod: b.timePeriod,
    classLink: b.classLink,
    meetType: b.meetType || 'CUSTOM',
    jitsiServer: b.jitsiServer || 'meet.jit.si',
    startDate: b.startDate,
    createdAt: b.createdAt,
  };
}

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// GET /api/batches
// Without ?page & ?limit, behaves exactly as before (returns the full
// array) — existing callers (tutor/mentor/student dashboards, schedules)
// are unaffected. Pass ?page=&limit=[&search=] to get a paginated
// { data, hasMore, total } response instead, for admin lists with
// hundreds of batches.
router.get('/', authenticateToken, async (req, res) => {
  try {
    let filter = {};
    if (req.user.role === 'TUTOR') filter = { tutor: req.user.id };
    else if (req.user.role === 'MENTOR') filter = { mentors: req.user.id };
    else if (req.user.role === 'STUDENT') filter = { students: req.user.id };

    const { page, limit, search } = req.query;

    if (search && search.trim()) {
      const regex = new RegExp(escapeRegex(search.trim()), 'i');
      const [courseIds, tutorIds, mentorIds, categoryIds] = await Promise.all([
        Course.find({ name: regex }).distinct('_id'),
        User.find({ role: 'TUTOR', name: regex }).distinct('_id'),
        User.find({ role: 'MENTOR', name: regex }).distinct('_id'),
        BatchCategory.find({ name: regex }).distinct('_id'),
      ]);
      filter = {
        ...filter,
        $or: [
          { name: regex },
          { course: { $in: courseIds } },
          { tutor: { $in: tutorIds } },
          { mentors: { $in: mentorIds } },
          { category: { $in: categoryIds } },
        ],
      };
    }

    const query = Batch.find(filter).populate(populateFields).sort({ createdAt: -1 });

    if (page && limit) {
      const pageNum = Math.max(1, parseInt(page) || 1);
      const limitNum = Math.max(1, parseInt(limit) || 30);
      const skip = (pageNum - 1) * limitNum;

      const [batches, totalCount] = await Promise.all([
        query.skip(skip).limit(limitNum),
        Batch.countDocuments(filter),
      ]);

      return res.json({
        data: batches.map(formatBatch),
        hasMore: skip + batches.length < totalCount,
        total: totalCount,
      });
    }

    const batches = await query;
    res.json(batches.map(formatBatch));
  } catch (error) {
    console.error('Fetch batches error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/batches/:id
router.get('/:id', authenticateToken, async (req, res) => {
  try {
    const batch = await Batch.findById(req.params.id).populate(populateFields);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    if (req.user.role !== 'ADMIN') {
      const isTutor = batch.tutor._id.toString() === req.user.id;
      const isMentor = batch.mentors.some(m => m._id.toString() === req.user.id);
      const isStudent = batch.students.some(s => s._id.toString() === req.user.id);
      if (!isTutor && !isMentor && !isStudent) {
        return res.status(403).json({ message: 'Access denied: not assigned to this batch' });
      }
    }

    res.json(formatBatch(batch));
  } catch (error) {
    console.error('Fetch batch error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/batches
router.post('/', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { name, categoryId, courseId, tutorId, mentorIds, daysOfWeek, timePeriod, classLink, meetType, jitsiServer, startDate } = req.body;

  if (!name || !categoryId || !courseId || !tutorId || !daysOfWeek || !timePeriod) {
    return res.status(400).json({ message: 'name, categoryId, courseId, tutorId, daysOfWeek, and timePeriod are required' });
  }

  try {
    const category = await BatchCategory.findById(categoryId);
    if (!category) return res.status(400).json({ message: 'Category not found' });

    const course = await Course.findById(courseId);
    if (!course) return res.status(400).json({ message: 'Course not found' });

    const tutor = await User.findById(tutorId);
    if (!tutor || tutor.role !== 'TUTOR') return res.status(400).json({ message: 'Invalid tutor' });

    if (mentorIds?.length) {
      const mentors = await User.find({ _id: { $in: mentorIds }, role: 'MENTOR' });
      if (mentors.length !== mentorIds.length) {
        return res.status(400).json({ message: 'One or more mentors are invalid' });
      }
    }

    const daysStr = Array.isArray(daysOfWeek) ? daysOfWeek.join(',') : daysOfWeek;

    // Check for tutor scheduling conflicts
    const existingTutorBatches = await Batch.find({ tutor: tutorId });
    const conflict = hasScheduleConflict(daysStr, timePeriod, existingTutorBatches);
    if (conflict) {
      return res.status(400).json({ 
        message: `Tutor conflict detected: Overlaps with batch "${conflict.batchName}" on ${conflict.day} (${conflict.time}).` 
      });
    }

    const batch = await Batch.create({
      name,
      category: categoryId,
      course: courseId,
      tutor: tutorId,
      mentors: mentorIds || [],
      daysOfWeek: daysStr,
      timePeriod,
      classLink: classLink || '',
      meetType: meetType || 'CUSTOM',
      jitsiServer: jitsiServer || 'meet.jit.si',
      startDate: startDate ? new Date(startDate) : new Date(),
    });

    // Trigger schedule generation asynchronously so the schedules are immediately available
    generateSchedules(batch._id).catch(err => console.error('Failed to generate schedules:', err));

    const populated = await Batch.findById(batch._id).populate(populateFields);
    res.status(201).json(formatBatch(populated));
  } catch (error) {
    console.error('Create batch error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/batches/:id
router.put('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { name, categoryId, courseId, tutorId, mentorIds, daysOfWeek, timePeriod, classLink, meetType, jitsiServer, startDate } = req.body;
  try {
    const batch = await Batch.findById(req.params.id);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    if (courseId) {
      const course = await Course.findById(courseId);
      if (!course) return res.status(400).json({ message: 'Course not found' });
      batch.course = courseId;
    }
    if (categoryId) {
      const category = await BatchCategory.findById(categoryId);
      if (!category) return res.status(400).json({ message: 'Category not found' });
      batch.category = categoryId;
    }
    if (tutorId) {
      const tutor = await User.findById(tutorId);
      if (!tutor || tutor.role !== 'TUTOR') return res.status(400).json({ message: 'Invalid tutor' });
      batch.tutor = tutorId;
    }
    if (mentorIds) {
      const mentors = await User.find({ _id: { $in: mentorIds }, role: 'MENTOR' });
      if (mentors.length !== mentorIds.length) {
        return res.status(400).json({ message: 'One or more mentors are invalid' });
      }
      batch.mentors = mentorIds;
    }

    const tutorIdToCheck = tutorId || batch.tutor;
    const daysToCheck = daysOfWeek ? (Array.isArray(daysOfWeek) ? daysOfWeek.join(',') : daysOfWeek) : batch.daysOfWeek;
    const timeToCheck = timePeriod || batch.timePeriod;

    const existingTutorBatches = await Batch.find({ 
      tutor: tutorIdToCheck, 
      _id: { $ne: batch._id } 
    });
    
    const conflict = hasScheduleConflict(daysToCheck, timeToCheck, existingTutorBatches);
    if (conflict) {
      return res.status(400).json({ 
        message: `Tutor conflict detected: Overlaps with batch "${conflict.batchName}" on ${conflict.day} (${conflict.time}).` 
      });
    }

    if (name) batch.name = name;
    if (daysOfWeek) batch.daysOfWeek = Array.isArray(daysOfWeek) ? daysOfWeek.join(',') : daysOfWeek;
    if (timePeriod) batch.timePeriod = timePeriod;
    if (classLink !== undefined) batch.classLink = classLink;
    if (meetType !== undefined) batch.meetType = meetType;
    if (jitsiServer !== undefined) batch.jitsiServer = jitsiServer;
    if (startDate !== undefined) batch.startDate = new Date(startDate);

    await batch.save();

    // Trigger schedule generation asynchronously in case days/times changed
    generateSchedules(batch._id).catch(err => console.error('Failed to generate schedules:', err));

    const populated = await Batch.findById(batch._id).populate(populateFields);
    res.json(formatBatch(populated));
  } catch (error) {
    console.error('Update batch error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/batches/:id/link
router.put('/:id/link', authenticateToken, requireRole(['ADMIN', 'TUTOR', 'MENTOR']), async (req, res) => {
  const { classLink } = req.body;
  try {
    const batch = await Batch.findById(req.params.id);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    // Verify tutor/mentor belongs to batch if not admin
    if (req.user.role !== 'ADMIN') {
      const isTutor = batch.tutor.toString() === req.user.id;
      const isMentor = batch.mentors.some(m => m.toString() === req.user.id);
      if (!isTutor && !isMentor) {
        return res.status(403).json({ message: 'Access denied: not assigned to this batch' });
      }
    }

    batch.classLink = classLink;
    await batch.save();
    
    res.json({ message: 'Link updated successfully', classLink });
  } catch (error) {
    console.error('Update link error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/batches/:id
router.delete('/:id', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  try {
    const batch = await Batch.findByIdAndDelete(req.params.id);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });
    res.json({ message: 'Batch deleted successfully' });
  } catch (error) {
    console.error('Delete batch error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/batches/:id/students
router.post('/:id/students', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { studentIds } = req.body;
  if (!studentIds?.length) return res.status(400).json({ message: 'studentIds array is required' });

  try {
    const batch = await Batch.findById(req.params.id).populate('category');
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    const students = await User.find({ _id: { $in: studentIds }, role: 'STUDENT' });
    if (students.length !== studentIds.length) {
      return res.status(400).json({ message: 'One or more student IDs are invalid' });
    }

    // Add only students not already in the batch
    const existingIds = batch.students.map(s => s.toString());
    const newIds = studentIds.filter(id => !existingIds.includes(id));

    // Check member limits if category is set
    if (batch.category && batch.category.maxMembers) {
      if (existingIds.length + newIds.length > batch.category.maxMembers) {
        return res.status(400).json({ 
          message: `Cannot add students. The "${batch.category.name}" category is limited to ${batch.category.maxMembers} member(s).` 
        });
      }
    }

    batch.students.push(...newIds);
    await batch.save();

    // Re-trigger schedule generation to ensure schedules exist
    generateSchedules(batch._id).catch(err => console.error('Failed to generate schedules:', err));

    const populated = await Batch.findById(batch._id).populate(populateFields);
    res.json(formatBatch(populated));
  } catch (error) {
    console.error('Add students error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/batches/:id/students/:studentId
router.delete('/:id/students/:studentId', authenticateToken, requireRole(['ADMIN']), async (req, res) => {
  const { id, studentId } = req.params;
  try {
    const batch = await Batch.findById(id);
    if (!batch) return res.status(404).json({ message: 'Batch not found' });

    batch.students = batch.students.filter(s => s.toString() !== studentId);
    await batch.save();

    const populated = await Batch.findById(batch._id).populate(populateFields);
    res.json(formatBatch(populated));
  } catch (error) {
    console.error('Remove student error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
