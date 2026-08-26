import mongoose from 'mongoose';

// A live "Start Class" video session for a batch -- separate from
// ParentMeeting (different lifecycle: never pre-scheduled by the tutor
// ahead of time, always tied to today's actual Schedule entry, started
// on-demand from the tutor dashboard). Deliberately mirrors
// ParentMeeting's field names (title/channelName/agoraAppId/hostName/
// batchName/status) so the SAME generic ParentMeetingRoomScreen on the
// Flutter side (driven purely by a Map, not either model directly) can
// render either kind of meeting unmodified.
const classMeetingSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
    },
    batch: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Batch',
      required: true,
      index: true,
    },
    batchName: {
      type: String,
      default: 'Batch',
    },
    // The specific today's-class Schedule entry this meeting belongs to
    // -- lets "Start Class" be idempotent (re-clicking, or a page
    // refresh mid-class, rejoins the same meeting instead of creating a
    // duplicate) by looking up "is there already a live meeting for
    // today's schedule" rather than juggling date-range queries again.
    schedule: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Schedule',
      required: true,
      index: true,
    },
    hostId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    hostName: {
      type: String,
      required: true,
    },
    channelName: {
      type: String,
      required: true,
      unique: true,
    },
    agoraAppId: {
      type: String,
      default: '2bd28ff5ea124b5982b6ef930c49998d',
    },
    status: {
      type: String,
      enum: ['live', 'ended'],
      default: 'live',
      index: true,
    },
    startedAt: {
      type: Date,
      default: Date.now,
    },
    endedAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true }
);

const ClassMeeting = mongoose.model('ClassMeeting', classMeetingSchema);
export default ClassMeeting;
