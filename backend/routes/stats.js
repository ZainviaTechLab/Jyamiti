import express from 'express';
import User from '../models/User.js';
import Batch from '../models/Batch.js';
import Course from '../models/Course.js';
import Schedule from '../models/Schedule.js';
import Payment from '../models/Payment.js';
import Attendance from '../models/Attendance.js';
import LeaveRequest from '../models/LeaveRequest.js';
import ParentMeeting from '../models/ParentMeeting.js';
import ExamSubmission from '../models/ExamSubmission.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

router.use(authenticateToken, requireRole(['ADMIN']));

const monthKey = (date) => date.toISOString().slice(0, 7); // YYYY-MM

router.get('/dashboard', async (req, res) => {
  try {
    const now = new Date();
    const oneWeekAgo = new Date(now);
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
    const oneWeekAhead = new Date(now);
    oneWeekAhead.setDate(oneWeekAhead.getDate() + 7);
    const thirtyDaysAgo = new Date(now);
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const sixMonthsAgo = new Date(now);
    sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
    const startOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const startOfLastMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);

    // ---- Core totals ----
    const [
      totalUsers,
      totalStudents,
      totalTutors,
      totalMentors,
      activeUsers,
      inactiveUsers,
      suspendedUsers,
      incompleteProfiles,
      totalCourses,
      totalBatches,
      sessionsPastWeek,
      sessionsNextWeek,
    ] = await Promise.all([
      User.countDocuments(),
      User.countDocuments({ role: 'STUDENT' }),
      User.countDocuments({ role: 'TUTOR' }),
      User.countDocuments({ role: 'MENTOR' }),
      User.countDocuments({ status: 'ACTIVE' }),
      User.countDocuments({ status: 'INACTIVE' }),
      User.countDocuments({ status: 'SUSPENDED' }),
      User.countDocuments({ isProfileComplete: false }),
      Course.countDocuments(),
      Batch.countDocuments(),
      Schedule.countDocuments({ date: { $gte: oneWeekAgo, $lte: now } }),
      Schedule.countDocuments({ date: { $gte: now, $lte: oneWeekAhead } }),
    ]);

    // ---- Registration trends (last 6 months) ----
    const recentUsersForTrend = await User.find({
      createdAt: { $gte: sixMonthsAgo },
    }).select('createdAt role');
    const registrationTrends = {};
    recentUsersForTrend.forEach((u) => {
      const key = monthKey(u.createdAt);
      if (!registrationTrends[key]) {
        registrationTrends[key] = { student: 0, tutor: 0, mentor: 0, total: 0 };
      }
      registrationTrends[key].total++;
      if (u.role === 'STUDENT') registrationTrends[key].student++;
      if (u.role === 'TUTOR') registrationTrends[key].tutor++;
      if (u.role === 'MENTOR') registrationTrends[key].mentor++;
    });

    // ---- User growth (this month vs last month) ----
    const [newThisMonth, newLastMonth] = await Promise.all([
      User.countDocuments({ createdAt: { $gte: startOfThisMonth } }),
      User.countDocuments({
        createdAt: { $gte: startOfLastMonth, $lt: startOfThisMonth },
      }),
    ]);
    const growthPercent =
      newLastMonth === 0
        ? newThisMonth > 0
          ? 100
          : 0
        : Math.round(((newThisMonth - newLastMonth) / newLastMonth) * 1000) / 10;

    // ---- Revenue ----
    const currentMonthYear = monthKey(now);
    const [collectedAgg, pendingAgg, overdueAgg, thisMonthAgg, overdueAgingAgg] = await Promise.all([
      Payment.aggregate([
        { $match: { status: 'PAID' } },
        { $group: { _id: null, total: { $sum: '$amountDue' } } },
      ]),
      Payment.aggregate([
        { $match: { status: 'PENDING' } },
        { $group: { _id: null, total: { $sum: '$amountDue' } } },
      ]),
      Payment.aggregate([
        { $match: { status: 'PENDING', dueDate: { $lt: now } } },
        {
          $group: {
            _id: null,
            total: { $sum: '$amountDue' },
            count: { $sum: 1 },
          },
        },
      ]),
      Payment.aggregate([
        { $match: { monthYear: currentMonthYear } },
        {
          $group: {
            _id: null,
            due: { $sum: '$amountDue' },
            collected: {
              $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, '$amountDue', 0] },
            },
          },
        },
      ]),
      // Aging breakdown of overdue pending payments
      Payment.aggregate([
        { $match: { status: 'PENDING', dueDate: { $lt: now } } },
        {
          $project: {
            amountDue: 1,
            daysOverdue: { $divide: [{ $subtract: [now, '$dueDate'] }, 1000 * 60 * 60 * 24] },
          },
        },
        {
          $bucket: {
            groupBy: '$daysOverdue',
            boundaries: [0, 7, 30, 60, Number.MAX_SAFE_INTEGER],
            default: 'unknown',
            output: { count: { $sum: 1 }, amount: { $sum: '$amountDue' } },
          },
        },
      ]),
    ]);
    const totalCollected = collectedAgg[0]?.total || 0;
    const totalPending = pendingAgg[0]?.total || 0;
    const overdueAmount = overdueAgg[0]?.total || 0;
    const overdueCount = overdueAgg[0]?.count || 0;
    const thisMonthDue = thisMonthAgg[0]?.due || 0;
    const thisMonthCollected = thisMonthAgg[0]?.collected || 0;
    const collectionRate =
      totalCollected + totalPending === 0
        ? 0
        : Math.round((totalCollected / (totalCollected + totalPending)) * 1000) / 10;

    const agingLabels = { 0: '≤7 days', 7: '8-30 days', 30: '31-60 days', 60: '60+ days' };
    const overdueAging = [0, 7, 30, 60].map((boundary) => {
      const bucket = overdueAgingAgg.find((a) => a._id === boundary);
      return {
        label: agingLabels[boundary],
        count: bucket?.count || 0,
        amount: bucket?.amount || 0,
      };
    });

    // Revenue trend, last 6 months (due vs collected per month)
    const sixMonthKeys = [];
    for (let i = 5; i >= 0; i--) {
      sixMonthKeys.push(monthKey(new Date(now.getFullYear(), now.getMonth() - i, 1)));
    }
    const revenueByMonth = await Payment.aggregate([
      { $match: { monthYear: { $in: sixMonthKeys } } },
      {
        $group: {
          _id: '$monthYear',
          due: { $sum: '$amountDue' },
          collected: {
            $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, '$amountDue', 0] },
          },
        },
      },
    ]);
    const revenueTrend = {};
    sixMonthKeys.forEach((m) => {
      revenueTrend[m] = { due: 0, collected: 0 };
    });
    revenueByMonth.forEach((r) => {
      revenueTrend[r._id] = { due: r.due, collected: r.collected };
    });

    // ---- Attendance (joined against Schedule date, not Attendance.createdAt) ----
    const buildAttendanceSummary = async (sinceDate) => {
      const rows = await Attendance.aggregate([
        {
          $lookup: {
            from: 'schedules',
            localField: 'schedule',
            foreignField: '_id',
            as: 'sched',
          },
        },
        { $unwind: '$sched' },
        { $match: { 'sched.date': { $gte: sinceDate, $lte: now } } },
        { $group: { _id: '$status', count: { $sum: 1 } } },
      ]);
      const summary = { present: 0, absent: 0, leave: 0, pending: 0 };
      rows.forEach((r) => {
        const key = String(r._id || '').toLowerCase();
        if (summary[key] !== undefined) summary[key] = r.count;
      });
      const marked = summary.present + summary.absent + summary.leave;
      const rate = marked === 0 ? 0 : Math.round((summary.present / marked) * 1000) / 10;
      return { ...summary, marked, rate };
    };
    const [attendance7d, attendance30d, attendanceByTutorAgg] = await Promise.all([
      buildAttendanceSummary(oneWeekAgo),
      buildAttendanceSummary(thirtyDaysAgo),
      // Per-tutor attendance rate (last 30 days), via schedule -> batch -> tutor
      Attendance.aggregate([
        {
          $lookup: {
            from: 'schedules',
            localField: 'schedule',
            foreignField: '_id',
            as: 'sched',
          },
        },
        { $unwind: '$sched' },
        { $match: { 'sched.date': { $gte: thirtyDaysAgo, $lte: now } } },
        {
          $lookup: {
            from: 'batches',
            localField: 'sched.batch',
            foreignField: '_id',
            as: 'batch',
          },
        },
        { $unwind: '$batch' },
        {
          $group: {
            _id: '$batch.tutor',
            present: { $sum: { $cond: [{ $eq: ['$status', 'Present'] }, 1, 0] } },
            absent: { $sum: { $cond: [{ $eq: ['$status', 'Absent'] }, 1, 0] } },
          },
        },
      ]),
    ]);
    const attendanceByTutorMap = new Map(
      attendanceByTutorAgg.map((r) => [String(r._id), r])
    );

    // Per-tutor revenue (all-time), via batch -> tutor
    const revenueByTutorAgg = await Payment.aggregate([
      { $lookup: { from: 'batches', localField: 'batch', foreignField: '_id', as: 'batch' } },
      { $unwind: '$batch' },
      {
        $group: {
          _id: '$batch.tutor',
          collected: { $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, '$amountDue', 0] } },
          pending: { $sum: { $cond: [{ $eq: ['$status', 'PENDING'] }, '$amountDue', 0] } },
        },
      },
    ]);
    const revenueByTutorMap = new Map(revenueByTutorAgg.map((r) => [String(r._id), r]));

    // ---- Needs attention (actionable lists) ----
    const [
      pendingLeaveRequests,
      pendingLeaveRequestsCount,
      overduePaymentsList,
      upcomingParentMeetings,
      pendingGradingList,
      pendingGradingCount,
    ] = await Promise.all([
      LeaveRequest.find({ status: 'Pending' })
        .sort({ createdAt: -1 })
        .limit(5)
        .populate('student', 'name')
        .populate({ path: 'schedule', populate: { path: 'batch', select: 'name' } }),
      LeaveRequest.countDocuments({ status: 'Pending' }),
      Payment.find({ status: 'PENDING', dueDate: { $lt: now } })
        .sort({ dueDate: 1 })
        .limit(5)
        .populate('student', 'name')
        .populate('batch', 'name'),
      ParentMeeting.find({ status: 'scheduled', scheduledAt: { $gte: now } })
        .sort({ scheduledAt: 1 })
        .limit(5),
      ExamSubmission.find({ status: 'PENDING_REVIEW' })
        .sort({ createdAt: -1 })
        .limit(5)
        .populate('exam', 'title')
        .populate('student', 'name'),
      ExamSubmission.countDocuments({ status: 'PENDING_REVIEW' }),
    ]);

    // ---- Batches: enrollment, capacity, course popularity, tutor performance ----
    const batchesRaw = await Batch.find()
      .populate('tutor', 'name')
      .populate('category', 'name maxMembers')
      .populate('course', 'name')
      .lean();

    const batchSummaries = batchesRaw.map((b) => {
      const studentCount = (b.students || []).length;
      const maxMembers = b.category?.maxMembers ?? null;
      const fillRatio = maxMembers && maxMembers > 0 ? studentCount / maxMembers : null;
      return {
        id: b._id,
        name: b.name,
        tutorId: b.tutor?._id ? String(b.tutor._id) : null,
        tutorName: b.tutor?.name || 'Unassigned',
        courseId: b.course?._id ? String(b.course._id) : null,
        courseName: b.course?.name || 'Unknown Course',
        categoryName: b.category?.name || 'Uncategorized',
        studentCount,
        maxMembers,
        fillRatio,
      };
    });

    const topBatches = [...batchSummaries]
      .sort((a, b) => b.studentCount - a.studentCount)
      .slice(0, 5);

    const nearFullBatches = batchSummaries
      .filter((b) => b.fillRatio !== null && b.fillRatio >= 0.9)
      .sort((a, b) => b.fillRatio - a.fillRatio)
      .slice(0, 5);
    const underEnrolledBatches = batchSummaries
      .filter((b) => b.fillRatio !== null && b.fillRatio <= 0.3)
      .sort((a, b) => a.fillRatio - b.fillRatio)
      .slice(0, 5);

    const courseMap = new Map();
    batchSummaries.forEach((b) => {
      if (!b.courseId) return;
      if (!courseMap.has(b.courseId)) {
        courseMap.set(b.courseId, {
          courseId: b.courseId,
          courseName: b.courseName,
          batchCount: 0,
          studentCount: 0,
          capacity: 0,
        });
      }
      const c = courseMap.get(b.courseId);
      c.batchCount += 1;
      c.studentCount += b.studentCount;
      c.capacity += b.maxMembers || 0;
    });
    const coursePopularity = Array.from(courseMap.values())
      .map((c) => ({
        ...c,
        fillRate: c.capacity > 0 ? Math.round((c.studentCount / c.capacity) * 1000) / 10 : null,
      }))
      .sort((a, b) => b.studentCount - a.studentCount)
      .slice(0, 8);

    const tutorMap = new Map();
    batchSummaries.forEach((b) => {
      if (!b.tutorId) return;
      if (!tutorMap.has(b.tutorId)) {
        tutorMap.set(b.tutorId, {
          tutorId: b.tutorId,
          tutorName: b.tutorName,
          batchCount: 0,
          studentCount: 0,
        });
      }
      const t = tutorMap.get(b.tutorId);
      t.batchCount += 1;
      t.studentCount += b.studentCount;
    });
    const tutorPerformance = Array.from(tutorMap.values())
      .map((t) => {
        const att = attendanceByTutorMap.get(t.tutorId);
        const marked = att ? att.present + att.absent : 0;
        const attendanceRate = marked > 0 ? Math.round((att.present / marked) * 1000) / 10 : null;
        const rev = revenueByTutorMap.get(t.tutorId);
        return {
          ...t,
          attendanceRate,
          revenueCollected: rev?.collected || 0,
          revenuePending: rev?.pending || 0,
        };
      })
      .sort((a, b) => b.studentCount - a.studentCount);

    // ---- Recently registered users ----
    const recentUsers = await User.find()
      .sort({ createdAt: -1 })
      .limit(5)
      .select('name email role createdAt');

    res.json({
      totals: {
        users: totalUsers,
        students: totalStudents,
        tutors: totalTutors,
        mentors: totalMentors,
        courses: totalCourses,
        batches: totalBatches,
        sessionsPastWeek,
        sessionsNextWeek,
      },
      userBreakdown: {
        active: activeUsers,
        inactive: inactiveUsers,
        suspended: suspendedUsers,
        incompleteProfile: incompleteProfiles,
      },
      userGrowth: {
        thisMonth: newThisMonth,
        lastMonth: newLastMonth,
        growthPercent,
      },
      registrationTrends,
      revenue: {
        totalCollected,
        totalPending,
        overdueAmount,
        overdueCount,
        thisMonthCollected,
        thisMonthDue,
        collectionRate,
        overdueAging,
        monthlyTrend: revenueTrend,
      },
      attendance: {
        last7Days: attendance7d,
        last30Days: attendance30d,
      },
      needsAttention: {
        pendingLeaveRequests: {
          count: pendingLeaveRequestsCount,
          items: pendingLeaveRequests.map((lr) => ({
            id: lr._id,
            studentName: lr.student?.name || 'Unknown',
            batchName: lr.schedule?.batch?.name || '',
            reason: lr.reason,
            createdAt: lr.createdAt,
          })),
        },
        overduePayments: {
          count: overdueCount,
          items: overduePaymentsList.map((p) => ({
            id: p._id,
            studentName: p.student?.name || 'Unknown',
            batchName: p.batch?.name || '',
            amountDue: p.amountDue,
            dueDate: p.dueDate,
          })),
        },
        upcomingParentMeetings: {
          count: upcomingParentMeetings.length,
          items: upcomingParentMeetings.map((m) => ({
            id: m._id,
            title: m.title,
            batchName: m.batchName,
            hostName: m.hostName,
            scheduledAt: m.scheduledAt,
          })),
        },
        pendingGrading: {
          count: pendingGradingCount,
          items: pendingGradingList.map((s) => ({
            id: s._id,
            examTitle: s.exam?.title || 'Exam',
            studentName: s.student?.name || 'Unknown',
            submittedAt: s.createdAt,
          })),
        },
      },
      batches: {
        topByEnrollment: topBatches,
        nearFull: nearFullBatches,
        underEnrolled: underEnrolledBatches,
      },
      coursePopularity,
      tutorPerformance,
      recentUsers: recentUsers.map((u) => ({
        id: u._id,
        name: u.name,
        email: u.email,
        role: u.role,
        createdAt: u.createdAt,
      })),
    });
  } catch (error) {
    console.error('Stats error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
