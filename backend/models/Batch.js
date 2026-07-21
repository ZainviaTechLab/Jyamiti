import mongoose from 'mongoose';

const batchSchema = new mongoose.Schema({
  name: { type: String, required: true },
  category: { type: mongoose.Schema.Types.ObjectId, ref: 'BatchCategory', required: false },
  course: { type: mongoose.Schema.Types.ObjectId, ref: 'Course', required: true },
  tutor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  mentors: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  students: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  daysOfWeek: { type: String, required: true }, // comma-separated e.g. "Monday,Wednesday,Friday"
  timePeriod: { type: String, required: true }, // e.g. "04:00 PM - 06:00 PM"
  classLink: { type: String, default: '' },
  startDate: { type: Date, default: Date.now },
}, { timestamps: true });

export default mongoose.model('Batch', batchSchema);
