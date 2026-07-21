import mongoose from 'mongoose';

const scheduleSchema = new mongoose.Schema({
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true, index: true },
  date: { type: Date, required: true, index: true },
  startTime: { type: String, required: true },
  endTime: { type: String, required: true },
  isCancelled: { type: Boolean, default: false },
}, { timestamps: true });

export default mongoose.model('Schedule', scheduleSchema);
