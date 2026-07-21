import mongoose from 'mongoose';

const worksheetSchema = new mongoose.Schema({
  title: { type: String, required: true },
  description: { type: String, required: true },
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true, index: true },
  tutor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  dueDate: { type: Date, required: true },
  maxScore: { type: Number, default: 100 },
  fileUrl: { type: String },
  isDownloadable: { type: Boolean, default: false },
  sessionDate: { type: Date, required: true }
}, { timestamps: true });

export default mongoose.model('Worksheet', worksheetSchema);
