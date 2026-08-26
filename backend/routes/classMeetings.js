import express from 'express';
import ClassMeeting from '../models/ClassMeeting.js';
import Batch from '../models/Batch.js';
import Schedule from '../models/Schedule.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';
import { getIO } from '../socket.js';

const router = express.Router();

// Same App ID as parentMeetings.js -- one Agora project for the whole
// app, not per-feature. Token minting itself is already generic
// (channelName + isHost, doesn't care which collection a meeting record
// lives in) and reused as-is via /api/parent-meetings/rtc-token -- no
// need to duplicate that endpoint here.
const AGORA_APP_ID = process.env.AGORA_APP_ID || '2bd28ff5ea124b5982b6ef930c49998d';

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}
function endOfToday() {
  const d = new Date();
  d.setHours(23, 59, 59, 999);
  return d;
}

/// Broadcasts to every student enrolled in [batchId] via their personal
/// room -- the exact same mechanism chat's `new_message_notification`
/// already uses (see socket.js) -- so students don't need to explicitly
/// join any new batch-scoped room; their socket is already subscribed to
/// its own personal room from the app-wide `setup` handshake.
async function notifyBatchStudents(batchId, event, payload) {
  try {
    const io = getIO();
    const batch = await Batch.findById(batchId).select('students');
    for (const studentId of batch?.students || []) {
      io.to(studentId.toString()).emit(event, payload);
    }
  } catch (err) {
    console.error(`Error broadcasting ${event}:`, err);
  }
}

// 1. Start (or rejoin) today's class for a batch -- TUTOR/ADMIN only, and
// only for a batch that tutor actually owns, with a real Schedule entry
// today (not cancelled). Idempotent: if a live meeting already exists for
// today's schedule, returns that one instead of creating a duplicate.
router.post(
  '/start',
  authenticateToken,
  requireRole(['TUTOR', 'ADMIN', 'tutor', 'admin']),
  async (req, res) => {
    try {
      const { batchId } = req.body;
      if (!batchId) {
        return res.status(400).json({ message: 'batchId is required.' });
      }

      const batch = await Batch.findById(batchId);
      if (!batch) {
        return res.status(404).json({ message: 'Batch not found.' });
      }
      if (
        req.user.role?.toUpperCase() === 'TUTOR' &&
        batch.tutor?.toString() !== req.user.id
      ) {
        return res.status(403).json({ message: 'You do not tutor this batch.' });
      }

      const schedule = await Schedule.findOne({
        batch: batchId,
        date: { $gte: startOfToday(), $lte: endOfToday() },
        isCancelled: { $ne: true },
      });
      if (!schedule) {
        return res
          .status(400)
          .json({ message: 'This batch has no scheduled class today.' });
      }

      let meeting = await ClassMeeting.findOne({
        schedule: schedule._id,
        status: 'live',
      });
      let justStarted = false;

      if (!meeting) {
        // Includes Date.now() (base36, to stay short) so restarting a
        // class after ending it gets a fresh channel name instead of
        // colliding with the just-ended meeting's own document, which
        // still exists (status: 'ended') and still holds that exact
        // channelName in the schema's `unique: true` index. Re-clicking
        // "Start Class" WHILE already live is unaffected -- that's
        // handled by the findOne(status: 'live') lookup above, which
        // returns the existing document before this branch ever runs, so
        // it doesn't depend on the channelName being deterministic.
        //
        // Deliberately doesn't include batchId -- Agora channel names are
        // capped at 64 BYTES (INVALID_PARAMS if exceeded), and
        // `class_${batchId}_${schedule._id}_${Date.now()}` (the previous
        // version of this line) came to 69 bytes with two full 24-char
        // ObjectIds plus a decimal timestamp, silently exceeding that cap
        // -- Agora accepted the /start call fine (it never validates the
        // name) but then rejected the client's actual joinChannel() with
        // exactly that error. schedule._id alone already uniquely
        // identifies "which batch, which day" (a Schedule document isn't
        // shared across batches), so batchId adds nothing but length.
        const channelName = `cls_${schedule._id}_${Date.now().toString(36)}`;
        meeting = new ClassMeeting({
          title: `${batch.name} — Live Class`,
          batch: batchId,
          batchName: batch.name,
          schedule: schedule._id,
          hostId: req.user.id,
          hostName: req.user.name || 'Tutor',
          channelName,
          agoraAppId: AGORA_APP_ID,
          status: 'live',
        });
        await meeting.save();
        justStarted = true;
      }

      if (justStarted) {
        notifyBatchStudents(batchId, 'class_meeting:started', { meeting });
      }

      res.status(201).json({ message: 'Class started.', meeting });
    } catch (err) {
      console.error('Error starting class meeting:', err);
      res.status(500).json({ message: 'Failed to start class.', error: err.message });
    }
  }
);

// 2. End a class meeting -- host or ADMIN only.
router.put('/:id/end', authenticateToken, async (req, res) => {
  try {
    const meeting = await ClassMeeting.findById(req.params.id);
    if (!meeting) {
      return res.status(404).json({ message: 'Meeting not found.' });
    }
    if (
      req.user.role?.toUpperCase() === 'TUTOR' &&
      meeting.hostId.toString() !== req.user.id
    ) {
      return res.status(403).json({ message: 'Only the host can end this class.' });
    }
    meeting.status = 'ended';
    meeting.endedAt = new Date();
    await meeting.save();

    notifyBatchStudents(meeting.batch, 'class_meeting:ended', {
      meetingId: meeting._id.toString(),
    });

    res.json({ message: 'Class ended.', meeting });
  } catch (err) {
    console.error('Error ending class meeting:', err);
    res.status(500).json({ message: 'Failed to end class.', error: err.message });
  }
});

// 3. Is there a LIVE class right now for a batch -- used on dashboard
// load to catch "the class already started before I opened the app"
// (the socket event only covers "started while I'm already looking").
router.get('/batch/:batchId/live', authenticateToken, async (req, res) => {
  try {
    const meeting = await ClassMeeting.findOne({
      batch: req.params.batchId,
      status: 'live',
    }).sort({ startedAt: -1 });
    res.json({ meeting: meeting || null });
  } catch (err) {
    console.error('Error checking for a live class:', err);
    res.status(500).json({ message: 'Failed to check for a live class.' });
  }
});

// 4. For the logged-in TUTOR: per-batch "does this batch have a schedule
// today, and is a class already live for it" -- one call feeds every
// batch card's Start Class button state at once (mirrors
// /schedules/my-schedules' "resolve my batches, then query" shape rather
// than making the dashboard fire one request per batch card).
router.get('/my-today', authenticateToken, async (req, res) => {
  try {
    const batches = await Batch.find({ tutor: req.user.id }).select('_id name');
    const batchIds = batches.map((b) => b._id);

    const schedules = await Schedule.find({
      batch: { $in: batchIds },
      date: { $gte: startOfToday(), $lte: endOfToday() },
      isCancelled: { $ne: true },
    });
    const scheduleByBatch = new Map(schedules.map((s) => [s.batch.toString(), s]));

    const liveMeetings = await ClassMeeting.find({
      schedule: { $in: schedules.map((s) => s._id) },
      status: 'live',
    });
    const liveByBatch = new Map(liveMeetings.map((m) => [m.batch.toString(), m]));

    const result = batches.map((b) => ({
      batchId: b._id,
      batchName: b.name,
      hasScheduleToday: scheduleByBatch.has(b._id.toString()),
      liveMeeting: liveByBatch.get(b._id.toString()) || null,
    }));

    res.json({ batches: result });
  } catch (err) {
    console.error("Error checking tutor's today schedule:", err);
    res.status(500).json({ message: "Failed to check today's schedule." });
  }
});

// 5. For the logged-in STUDENT (or anyone): any class currently LIVE
// among the caller's own batches -- used on dashboard load to catch "the
// class already started before I opened the app" (the socket event only
// covers "started while I'm already looking"). Resolves batches by role
// exactly like /schedules/my-schedules does.
router.get('/my-live', authenticateToken, async (req, res) => {
  try {
    const role = req.user.role?.toUpperCase();
    const batchQuery =
      role === 'TUTOR' ? { tutor: req.user.id } : { students: req.user.id };
    const batchIds = (await Batch.find(batchQuery).select('_id')).map((b) => b._id);

    const meetings = await ClassMeeting.find({
      batch: { $in: batchIds },
      status: 'live',
    }).sort({ startedAt: -1 });

    res.json({ meetings });
  } catch (err) {
    console.error('Error checking for live classes:', err);
    res.status(500).json({ message: 'Failed to check for live classes.' });
  }
});

export default router;
