import mongoose from 'mongoose';

const noteSchema = new mongoose.Schema({
  title: { type: String, required: true },
  description: { type: String, required: true },
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true },
  tutor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  sessionDate: { type: Date, required: true },
  criteria: [{ type: String }],
  fileUrl: { type: String },
  isDownloadable: { type: Boolean, default: false }
}, { timestamps: true });

export default mongoose.model('Note', noteSchema);
