import mongoose from 'mongoose';

const noteSubmissionSchema = new mongoose.Schema({
  note: { type: mongoose.Schema.Types.ObjectId, ref: 'Note', index: true }, // Legacy or optional
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true, index: true },
  sessionDate: { type: Date, required: true },
  title: { type: String, required: true },
  description: { type: String, required: true },
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  fileUrl: { type: String, required: true },
  criteriaValues: {
    type: Map,
    of: String, // 'Y' or 'N'
    default: {}
  },
  status: { type: String, enum: ['SUBMITTED', 'REVIEWED'], default: 'SUBMITTED' }
}, { timestamps: true });

export default mongoose.model('NoteSubmission', noteSubmissionSchema);
