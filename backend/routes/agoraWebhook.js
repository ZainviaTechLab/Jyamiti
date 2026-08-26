import express from 'express';
import crypto from 'crypto';
import ClassMeeting from '../models/ClassMeeting.js';
import ParentMeeting from '../models/ParentMeeting.js';
import Batch from '../models/Batch.js';
import { getIO } from '../socket.js';

const router = express.Router();

/// Backend safety net for empty Agora channels, independent of whether
/// any client app is even still running: Agora's own Notifications
/// service (registered separately in the Agora Console -- see this
/// file's header comment below) POSTs here the moment a channel is
/// actually torn down server-side, so a meeting never stays "live" in
/// our own DB forever just because a tutor's client crashed, lost
/// network, or force-quit without ever calling PUT /:id/end.
///
/// SETUP (one-time, manual, in the Agora Console -- not something this
/// code can do on its own):
///   1. Console > Webhooks > New Webhook > Product: RTC.
///   2. Receiving URL: https://<your-api-domain>/api/agora/webhook
///      (the deployed backend's public base URL + this route).
///   3. Subscribe to at least "Channel Destroy" (eventType 102).
///   4. Copy the "Signing Secret" Console shows and set it as
///      AGORA_WEBHOOK_SECRET in the backend's .env -- without it, this
///      endpoint still works but accepts every request UNVERIFIED
///      (logs a warning each time), which is fine for initial testing
///      but should be set before relying on this in production, since
///      an unauthenticated POST to a guessed channelName could
///      otherwise mark a still-live meeting "ended" early.
///
/// Reference: https://docs.agora.io/en/video-calling/channel-management-api/webhook/channel-event-type
/// (eventType 102 = channel_destroy: the last user left, channel torn
/// down -- payload.channelName identifies which one).
router.post(
  '/webhook',
  // Agora signs the RAW request body -- this route needs the exact
  // bytes as sent, not the parsed object the app-wide express.json()
  // middleware would otherwise hand every other route. Mounted in
  // server.js BEFORE that global express.json() call specifically so
  // this raw parser sees the request first.
  express.raw({ type: 'application/json' }),
  async (req, res) => {
    try {
      const rawBody = req.body; // Buffer, thanks to express.raw() above
      const secret = process.env.AGORA_WEBHOOK_SECRET;

      if (secret) {
        const expectedSignature = crypto
          .createHmac('sha256', secret)
          .update(rawBody)
          .digest('hex');
        const gotSignature = req.get('Agora-Signature-V2');
        if (!gotSignature || gotSignature !== expectedSignature) {
          console.warn('Agora webhook: signature mismatch -- rejecting.');
          return res.status(401).json({ message: 'Invalid signature.' });
        }
      } else {
        console.warn(
          'Agora webhook: AGORA_WEBHOOK_SECRET not set -- accepting this ' +
            'request UNVERIFIED. Set that env var once the webhook is ' +
            'registered in the Agora Console (see this file\'s header comment).'
        );
      }

      const event = JSON.parse(rawBody.toString('utf8'));

      if (event.eventType === 102) {
        const channelName = event.payload?.channelName;
        if (channelName) {
          await handleChannelDestroyed(channelName);
        }
      }

      // Agora requires 200 + a JSON body within 10s to consider this
      // delivered -- anything else triggers retries (up to 3 attempts).
      res.status(200).json({ result: 0 });
    } catch (err) {
      console.error('Error handling Agora webhook:', err);
      // Still 200 -- an event we failed to parse/handle shouldn't loop
      // Agora's retry logic forever; log it and move on.
      res.status(200).json({ result: 0 });
    }
  }
);

async function handleChannelDestroyed(channelName) {
  const classMeeting = await ClassMeeting.findOneAndUpdate(
    { channelName, status: 'live' },
    { status: 'ended', endedAt: new Date() },
    { new: true }
  );
  if (classMeeting) {
    try {
      const io = getIO();
      const batch = await Batch.findById(classMeeting.batch).select('students');
      for (const studentId of batch?.students || []) {
        io.to(studentId.toString()).emit('class_meeting:ended', {
          meetingId: classMeeting._id.toString(),
        });
      }
    } catch (err) {
      console.error('Error broadcasting class_meeting:ended from webhook:', err);
    }
    return;
  }

  // Not a class meeting -- try ParentMeeting instead (same channelName
  // namespace overall, but the two collections are otherwise unrelated).
  await ParentMeeting.findOneAndUpdate(
    { channelName, status: 'live' },
    { status: 'ended' }
  );
}

export default router;
