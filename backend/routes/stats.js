import express from 'express';
import User from '../models/User.js';
import Batch from '../models/Batch.js';
import Course from '../models/Course.js';
import Schedule from '../models/Schedule.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

router.use(authenticateToken, requireRole(['ADMIN']));

router.get('/dashboard', async (req, res) => {
  try {
    const totalUsers = await User.countDocuments();
    const totalStudents = await User.countDocuments({ role: 'STUDENT' });
    const totalTutors = await User.countDocuments({ role: 'TUTOR' });
    const totalMentors = await User.countDocuments({ role: 'MENTOR' });
    const totalCourses = await Course.countDocuments();
    const totalBatches = await Batch.countDocuments();
    const totalSessions = await Schedule.countDocuments();

    // Sessions in the past week
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
    const sessionsPastWeek = await Schedule.countDocuments({ date: { $gte: oneWeekAgo } });

    // Registrations over the last 6 months
    const sixMonthsAgo = new Date();
    sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);

    const users = await User.find({ createdAt: { $gte: sixMonthsAgo } }).select('createdAt role');
    
    // Group users by month (format: YYYY-MM)
    const registrationTrends = {};
    users.forEach(u => {
      const monthYear = u.createdAt.toISOString().slice(0, 7);
      if (!registrationTrends[monthYear]) {
        registrationTrends[monthYear] = { student: 0, tutor: 0, mentor: 0, total: 0 };
      }
      registrationTrends[monthYear].total++;
      if (u.role === 'STUDENT') registrationTrends[monthYear].student++;
      if (u.role === 'TUTOR') registrationTrends[monthYear].tutor++;
      if (u.role === 'MENTOR') registrationTrends[monthYear].mentor++;
    });

    res.json({
      totals: {
        users: totalUsers,
        students: totalStudents,
        tutors: totalTutors,
        mentors: totalMentors,
        courses: totalCourses,
        batches: totalBatches,
        sessions: totalSessions,
        sessionsPastWeek: sessionsPastWeek,
      },
      registrationTrends,
    });
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
