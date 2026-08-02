import mongoose from 'mongoose';

const parentMeetingSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      default: '',
    },
    batchId: {
      type: mongoose.Schema.Types.Mixed,
      default: null,
    },
    batchName: {
      type: String,
      default: 'General Batch',
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
    scheduledAt: {
      type: Date,
      required: true,
    },
    durationMinutes: {
      type: Number,
      default: 45,
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
      enum: ['scheduled', 'live', 'ended'],
      default: 'scheduled',
    },
  },
  { timestamps: true }
);

const ParentMeeting = mongoose.model('ParentMeeting', parentMeetingSchema);
export default ParentMeeting;
