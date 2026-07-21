import mongoose from 'mongoose';

const worksheetSubmissionSchema = new mongoose.Schema({
  worksheet: { type: mongoose.Schema.Types.ObjectId, ref: 'Worksheet', required: true, index: true },
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  fileUrl: { type: String, required: true },
  annotatedFileUrl: { type: String, default: null },
  totalScore: { type: Number, default: 0 },
  remark: { type: String, default: '' },
  status: { type: String, enum: ['SUBMITTED', 'GRADED'], default: 'SUBMITTED' }
}, { timestamps: true });

export default mongoose.model('WorksheetSubmission', worksheetSubmissionSchema);
