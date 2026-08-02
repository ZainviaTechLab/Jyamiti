import express from 'express';
import ParentMeeting from '../models/ParentMeeting.js';
import Batch from '../models/Batch.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';
import agoraToken from 'agora-token';
const { RtcTokenBuilder, RtcRole } = agoraToken;

const router = express.Router();

const AGORA_APP_ID = process.env.AGORA_APP_ID || '2bd28ff5ea124b5982b6ef930c49998d';
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE || '15e5bf0169094b03bdaa98575bab371c';

// 0. Generate Agora RTC Token for dynamic security authentication
router.get('/rtc-token', async (req, res) => {
  try {
    const { channelName, isHost } = req.query;
    if (!channelName) {
      return res.status(400).json({ message: 'channelName is required.' });
    }

    const role = isHost === 'true' ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const expirationTimeInSeconds = 3600 * 24; // 24 hours validity
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    // Generate token with integer uid = 0 (Agora assigns UID on client side)
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      0,
      role,
      privilegeExpiredTs,
      privilegeExpiredTs
    );

    res.json({ token, appId: AGORA_APP_ID, channelName });
  } catch (err) {
    console.error('Error generating Agora RTC token:', err);
    res.status(500).json({ message: 'Failed to generate RTC token.', error: err.message });
  }
});

// 1. Create a new Parent Meeting
router.post('/create', authenticateToken, requireRole(['TUTOR', 'ADMIN', 'tutor', 'admin']), async (req, res) => {
  try {
    const { title, description, batchId, scheduledAt, durationMinutes } = req.body;

    if (!title || !scheduledAt) {
      return res.status(400).json({ message: 'Title and Scheduled Time are required.' });
    }

    let targetBatchId = batchId;
    let batchName = 'General Batch';

    if (batchId) {
      try {
        const batch = await Batch.findById(batchId);
        if (batch) {
          batchName = batch.name || 'Batch';
        }
      } catch (_) {}
    } else {
      const userBatch = await Batch.findOne({ tutor: req.user.id });
      if (userBatch) {
        targetBatchId = userBatch._id;
        batchName = userBatch.name;
      }
    }

    const channelName = `meet_${targetBatchId || 'gen'}_${Date.now()}`;

    const meeting = new ParentMeeting({
      title,
      description: description || '',
      batchId: targetBatchId || req.user.id,
      batchName,
      hostId: req.user.id,
      hostName: req.user.name || 'Tutor',
      scheduledAt: new Date(scheduledAt),
      durationMinutes: durationMinutes || 45,
      channelName,
      agoraAppId: AGORA_APP_ID,
      status: 'scheduled',
    });

    await meeting.save();
    res.status(201).json({ message: 'Parent Meeting scheduled successfully.', meeting });
  } catch (err) {
    console.error('Error creating parent meeting:', err);
    res.status(500).json({ message: 'Failed to schedule parent meeting.', error: err.message });
  }
});

// 2. Fetch meetings for a specific batch
router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const { batchId } = req.params;
    const meetings = await ParentMeeting.find({ batchId }).sort({ scheduledAt: -1 });
    res.json({ meetings });
  } catch (err) {
    console.error('Error fetching batch meetings:', err);
    res.status(500).json({ message: 'Failed to fetch batch meetings.' });
  }
});

// 3. Fetch all meetings relevant to current user (Tutor/Admin or Student/Parent)
router.get('/my-meetings', authenticateToken, async (req, res) => {
  try {
    const meetings = await ParentMeeting.find().sort({ scheduledAt: -1 });
    res.json({ meetings });
  } catch (err) {
    console.error('Error fetching my meetings:', err);
    res.status(500).json({ message: 'Failed to fetch meetings.' });
  }
});

// 4. Update meeting status (live, ended, scheduled)
router.put('/:id/status', authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    if (!['scheduled', 'live', 'ended'].includes(status)) {
      return res.status(400).json({ message: 'Invalid status value.' });
    }

    const meeting = await ParentMeeting.findById(id);
    if (!meeting) {
      return res.status(404).json({ message: 'Meeting not found.' });
    }

    meeting.status = status;
    await meeting.save();

    res.json({ message: `Meeting status updated to ${status}`, meeting });
  } catch (err) {
    console.error('Error updating meeting status:', err);
    res.status(500).json({ message: 'Failed to update meeting status.' });
  }
});

// 5. Delete meeting (TUTOR or ADMIN)
router.delete('/:id', authenticateToken, requireRole(['TUTOR', 'ADMIN']), async (req, res) => {
  try {
    const { id } = req.params;
    await ParentMeeting.findByIdAndDelete(id);
    res.json({ message: 'Meeting deleted successfully.' });
  } catch (err) {
    console.error('Error deleting meeting:', err);
    res.status(500).json({ message: 'Failed to delete meeting.' });
  }
});

export default router;
