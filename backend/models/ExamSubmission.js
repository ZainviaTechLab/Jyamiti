import mongoose from 'mongoose';

const examSubmissionSchema = new mongoose.Schema({
  exam: { type: mongoose.Schema.Types.ObjectId, ref: 'Exam', required: true, index: true },
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  answers: [{
    questionId: { type: mongoose.Schema.Types.ObjectId, ref: 'Question', required: true },
    selectedOptions: [{ type: String }], // for MCQ/TF
    textAnswer: { type: String }, // for Short Answer
    marksObtained: { type: Number, default: 0 },
    isCorrect: { type: Boolean, default: false } // Auto-evaluated for objective questions
  }],
  totalScore: { type: Number, default: 0 },
  status: { type: String, enum: ['PENDING_REVIEW', 'GRADED'], default: 'GRADED' },
  gradedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }
}, { timestamps: true });

export default mongoose.model('ExamSubmission', examSubmissionSchema);
