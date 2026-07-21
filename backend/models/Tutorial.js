import mongoose from 'mongoose';

const tutorialSchema = new mongoose.Schema({
  batch:       { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true },
  tutor:       { type: mongoose.Schema.Types.ObjectId, ref: 'User',  required: true },
  title:       { type: String, required: true },
  videoUrl:    { type: String, required: true },
  sessionDate: { type: String, default: '' },  // e.g. "2026-06-15"
  chapter:     { type: String, default: '' },  // chapter name from syllabus
  description: { type: String, default: '' },
}, { timestamps: true });

export default mongoose.model('Tutorial', tutorialSchema);
