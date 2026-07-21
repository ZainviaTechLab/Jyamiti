import mongoose from 'mongoose';

const questionSchema = new mongoose.Schema({
  course: { type: mongoose.Schema.Types.ObjectId, ref: 'Course', required: true, index: true },
  chapter: { type: String, default: '' },
  topic: { type: String, default: '' },
  type: { 
    type: String, 
    enum: ['MCQ_SINGLE', 'MCQ_MULTI', 'TRUE_FALSE', 'SHORT_ANSWER'], 
    required: true 
  },
  text: { type: String, required: true },
  options: [{ type: String }], // Only for MCQ
  correctAnswers: [{ type: String }], // For MCQ and TRUE_FALSE
  marks: { type: Number, default: 1 }
}, { timestamps: true });

export default mongoose.model('Question', questionSchema);
