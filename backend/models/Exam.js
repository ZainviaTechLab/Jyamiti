import mongoose from 'mongoose';

const examSchema = new mongoose.Schema({
  title: { type: String, required: true },
  description: { type: String },
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true },
  tutor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  questions: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Question' }],
  duration: { type: Number, required: true }, // in minutes
  isActive: { type: Boolean, default: true }
}, { timestamps: true });

export default mongoose.model('Exam', examSchema);
