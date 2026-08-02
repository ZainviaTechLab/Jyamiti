import mongoose from 'mongoose';

const responseHistorySchema = new mongoose.Schema({
  roundIndex: { type: Number, required: true },
  questionId: { type: String },
  selectedOption: { type: String },
  isCorrect: { type: Boolean, default: false },
  timeTakenSec: { type: Number, default: 0 },
  pointsEarned: { type: Number, default: 0 },
  submittedAt: { type: Date, default: Date.now }
});

const participantSchema = new mongoose.Schema({
  userId: { type: String, required: true },
  name: { type: String, required: true },
  avatar: { type: String, default: '' },
  totalScore: { type: Number, default: 0 },
  currentRank: { type: Number, default: 1 },
  streak: { type: Number, default: 0 },
  responseHistory: [responseHistorySchema]
});

const questionSchema = new mongoose.Schema({
  id: { type: String },
  text: { type: String, required: true },
  options: [{ type: String }],
  correctOptionIndex: { type: Number, required: true },
  explanation: { type: String, default: '' },
  category: { type: String, default: 'General Math' },
  subtopic: { type: String, default: '' },
  points: { type: Number, default: 1000 }
});

const competitionSchema = new mongoose.Schema({
  roomCode: { type: String, required: true, unique: true, uppercase: true },
  title: { type: String, required: true },
  batchId: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true },
  tutorId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  grade: { type: Number, default: 10 },
  status: {
    type: String,
    enum: ['LOBBY', 'IN_PROGRESS', 'ROUND_RESULT', 'COMPLETED'],
    default: 'LOBBY'
  },
  timePerQuestion: { type: Number, default: 60 }, // in seconds
  numberOfRounds: { type: Number, default: 3 },
  roundDurationMinutes: { type: Number, default: 1 },
  currentRoundIndex: { type: Number, default: 0 },
  questions: [questionSchema],
  participants: [participantSchema],
  analytics: {
    topicPerformance: [{
      topic: { type: String },
      totalQuestions: { type: Number, default: 0 },
      correctCount: { type: Number, default: 0 },
      avgTimeSec: { type: Number, default: 0 }
    }],
    totalParticipants: { type: Number, default: 0 },
    overallAccuracyPct: { type: Number, default: 0 }
  },
  startedAt: { type: Date },
  completedAt: { type: Date }
}, {
  timestamps: true
});

const Competition = mongoose.model('Competition', competitionSchema);

export default Competition;
