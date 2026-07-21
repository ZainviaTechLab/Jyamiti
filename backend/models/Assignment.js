import mongoose from 'mongoose';

const assignmentSchema = new mongoose.Schema({
  tutor: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  batch: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Batch',
    required: true
  },
  student: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    default: null // null means assigned to the whole batch
  },
  itemType: {
    type: String,
    enum: ['video', 'slide', 'practice_question', 'chapter', 'topic', 'subtopic'],
    required: true
  },
  itemTitle: {
    type: String,
    required: true
  },
  itemData: {
    type: mongoose.Schema.Types.Mixed
  },
  dueDate: {
    type: Date,
    required: true
  },
  status: {
    type: String,
    enum: ['pending', 'completed'],
    default: 'pending'
  },
  score: {
    type: Number,
    default: null
  },
  totalQuestions: {
    type: Number,
    default: null
  }
}, { timestamps: true });

export default mongoose.model('Assignment', assignmentSchema);
