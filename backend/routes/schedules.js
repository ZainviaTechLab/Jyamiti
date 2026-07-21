import express from 'express';
import { authenticateToken as authenticate, requireRole as authorizeRole } from '../middleware/authMiddleware.js';
import Schedule from '../models/Schedule.js';
import Attendance from '../models/Attendance.js';
import LeaveRequest from '../models/LeaveRequest.js';
import Batch from '../models/Batch.js';
import NoteSubmission from '../models/NoteSubmission.js';

const router = express.Router();

// GET /api/schedules/my-schedules
// Fetch schedules for the logged-in user
router.get('/my-schedules', authenticate, async (req, res) => {
  try {
    const userId = req.user.id;
    const role = req.user.role;
    
    let batches = [];
    if (role === 'STUDENT') {
      batches = await Batch.find({ students: userId }).select('_id name');
    } else if (role === 'TUTOR') {
      batches = await Batch.find({ tutor: userId }).select('_id name');
    } else if (role === 'MENTOR') {
      batches = await Batch.find({ mentors: userId }).select('_id name');
    } else if (role === 'ADMIN') {
      batches = await Batch.find().select('_id name');
    }

    const batchIds = batches.map(b => b._id);

    // Get schedules from last Sunday up to 14 days
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startOfWeek = new Date(today);
    startOfWeek.setDate(today.getDate() - today.getDay());
    
    const endOfNextWeek = new Date(startOfWeek);
    endOfNextWeek.setDate(startOfWeek.getDate() + 14);

    const schedules = await Schedule.find({
      batch: { $in: batchIds },
      date: { $gte: startOfWeek, $lt: endOfNextWeek }
    }).populate('batch', 'name course classLink').sort({ date: 1 });

    // Fetch related attendance and leaves if needed
    const scheduleIds = schedules.map(s => s._id);
    let attendances = [];
    let leaveRequests = [];
    let noteSubmissions = [];

    if (role === 'STUDENT') {
      attendances = await Attendance.find({ schedule: { $in: scheduleIds }, student: userId });
      leaveRequests = await LeaveRequest.find({ schedule: { $in: scheduleIds }, student: userId });
      noteSubmissions = await NoteSubmission.find({ student: userId });
    } else {
      attendances = await Attendance.find({ schedule: { $in: scheduleIds } }).populate('student', 'name email');
      leaveRequests = await LeaveRequest.find({ schedule: { $in: scheduleIds } }).populate('student', 'name email');
    }

    res.json({
      schedules,
      attendances,
      leaveRequests,
      noteSubmissions
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// GET /api/schedules/my-attendance-summary
// Fetch attendance summary statistics for the logged in student
router.get('/my-attendance-summary', authenticate, authorizeRole(['STUDENT']), async (req, res) => {
  try {
    const studentId = req.user.id;
    const attendances = await Attendance.find({ student: studentId }).populate('schedule', 'date');

    // Sort attendances by schedule date descending
    attendances.sort((a, b) => {
      const dateA = a.schedule?.date ? new Date(a.schedule.date) : new Date(0);
      const dateB = b.schedule?.date ? new Date(b.schedule.date) : new Date(0);
      return dateB - dateA;
    });

    let present = 0;
    let absent = 0;
    let leave = 0;
    let totalSweets = 0;

    const recentAttendance = [];
    const monthlyStats = {};

    attendances.forEach(a => {
      // Aggregate stats
      if (a.status === 'Present') {
        present++;
        totalSweets += a.sweets || 0;
      }
      else if (a.status === 'Absent') absent++;
      else if (a.status === 'Leave') leave++;

      // Build recent list (max 5)
      if (recentAttendance.length < 5 && a.schedule && a.schedule.date) {
        const dateObj = new Date(a.schedule.date);
        let classDateTime = dateObj;
        if (a.schedule.startTime) {
          const [hours, minutes] = a.schedule.startTime.split(':');
          if (hours && minutes) {
            classDateTime.setHours(parseInt(hours, 10), parseInt(minutes, 10), 0, 0);
          }
        }
        if (classDateTime <= new Date()) {
          recentAttendance.push({
            date: dateObj.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }),
            status: a.status.toLowerCase(),
            remarks: '', // Could be linked to LeaveRequest if needed
            sweets: a.sweets || 0
          });
        }
      }

      // Build monthly trends
      if (a.schedule && a.schedule.date) {
        const dateObj = new Date(a.schedule.date);
        const monthKey = dateObj.toLocaleDateString('en-US', { month: 'short' }); // e.g. "Oct"
        if (!monthlyStats[monthKey]) {
          monthlyStats[monthKey] = { present: 0, total: 0 };
        }
        monthlyStats[monthKey].total++;
        if (a.status === 'Present') {
          monthlyStats[monthKey].present++;
        }
      }
    });

    const total = present + absent + leave;
    let percentage = 0;
    if (total > 0) {
      percentage = (present / total) * 100;
    }

    const monthlyTrend = Object.keys(monthlyStats).map(month => {
      const stats = monthlyStats[month];
      return {
        month,
        percentage: stats.total > 0 ? (stats.present / stats.total) * 100 : 0,
        present: stats.present,
        total: stats.total
      };
    });

    res.json({
      present,
      absent,
      leave,
      total,
      percentage,
      streak: 0,
      totalSweets,
      recentAttendance,
      monthlyTrend
    });
  } catch (error) {
    console.error('Attendance summary error:', error);
    res.status(500).json({ message: 'Server error' });
  }
});

// GET /api/schedules/batch/:batchId/past
// Fetch all past schedules for a specific batch
router.get('/batch/:batchId/past', authenticate, async (req, res) => {
  try {
    const { batchId } = req.params;
    const today = new Date();
    today.setHours(23, 59, 59, 999); // Include all sessions up to the end of today

    const schedules = await Schedule.find({
      batch: batchId,
      date: { $lte: today }
    }).sort({ date: -1 });

    res.json(schedules);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// POST /api/schedules/:scheduleId/leave
// Student applies for leave
router.post('/:scheduleId/leave', authenticate, authorizeRole(['STUDENT']), async (req, res) => {
  try {
    const { reason } = req.body;
    const scheduleId = req.params.scheduleId;
    const studentId = req.user.id;

    const existingRequest = await LeaveRequest.findOne({ schedule: scheduleId, student: studentId });
    if (existingRequest) {
      return res.status(400).json({ message: 'Leave request already submitted for this schedule' });
    }

    const leaveRequest = await LeaveRequest.create({
      schedule: scheduleId,
      student: studentId,
      reason
    });

    res.status(201).json(leaveRequest);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// PUT /api/schedules/:scheduleId/leave/:leaveId
// Mentor approves/rejects leave
router.put('/:scheduleId/leave/:leaveId', authenticate, authorizeRole(['MENTOR', 'ADMIN']), async (req, res) => {
  try {
    const { status } = req.body; // 'Approved' or 'Rejected'
    const { scheduleId, leaveId } = req.params;

    const leaveRequest = await LeaveRequest.findById(leaveId);
    if (!leaveRequest) {
      return res.status(404).json({ message: 'Leave request not found' });
    }

    leaveRequest.status = status;
    leaveRequest.grantedBy = req.user.id;
    await leaveRequest.save();

    if (status === 'Approved') {
      // Update attendance status
      await Attendance.findOneAndUpdate(
        { schedule: scheduleId, student: leaveRequest.student },
        { status: 'Leave', markedBy: req.user.id }
      );
    }

    res.json(leaveRequest);
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// PUT /api/schedules/:scheduleId/attendance
// Tutor/Mentor marks attendance for multiple students
router.put('/:scheduleId/attendance', authenticate, authorizeRole(['TUTOR', 'MENTOR', 'ADMIN']), async (req, res) => {
  try {
    const { attendanceData } = req.body; // Array of { studentId, status }
    const { scheduleId } = req.params;

    const promises = attendanceData.map(record => {
      return Attendance.findOneAndUpdate(
        { schedule: scheduleId, student: record.studentId },
        { 
          status: record.status, 
          isLate: record.isLate || false,
          sweets: record.sweets || 0,
          markedBy: req.user.id 
        },
        { new: true, upsert: true }
      );
    });

    await Promise.all(promises);

    res.json({ message: 'Attendance updated successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// PUT /api/schedules/:scheduleId/cancel
// Tutor/Mentor cancels a schedule
router.put('/:scheduleId/cancel', authenticate, authorizeRole(['TUTOR', 'MENTOR', 'ADMIN']), async (req, res) => {
  try {
    const { scheduleId } = req.params;
    const schedule = await Schedule.findById(scheduleId);
    if (!schedule) {
      return res.status(404).json({ message: 'Schedule not found' });
    }
    
    schedule.isCancelled = true;
    await schedule.save();

    res.json({ message: 'Schedule cancelled successfully', schedule });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

// POST /api/schedules/:scheduleId/postpone
// Tutor/Mentor postpones a schedule
router.post('/:scheduleId/postpone', authenticate, authorizeRole(['TUTOR', 'MENTOR', 'ADMIN']), async (req, res) => {
  try {
    const { scheduleId } = req.params;
    const { newDate } = req.body;
    
    if (!newDate) {
      return res.status(400).json({ message: 'New date is required' });
    }

    const schedule = await Schedule.findById(scheduleId);
    if (!schedule) {
      return res.status(404).json({ message: 'Schedule not found' });
    }
    
    // Mark original as cancelled
    schedule.isCancelled = true;
    await schedule.save();

    // Create new schedule with new date
    const newSchedule = await Schedule.create({
      batch: schedule.batch,
      date: new Date(newDate),
      startTime: schedule.startTime,
      endTime: schedule.endTime,
      isCancelled: false
    });

    res.json({ message: 'Schedule postponed successfully', oldSchedule: schedule, newSchedule });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Server error' });
  }
});

export default router;
