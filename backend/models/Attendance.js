import mongoose from 'mongoose';

const attendanceSchema = new mongoose.Schema({
  schedule: { type: mongoose.Schema.Types.ObjectId, ref: 'Schedule', required: true, index: true },
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  status: { 
    type: String, 
    enum: ['Pending', 'Present', 'Absent', 'Leave'], 
    default: 'Pending' 
  },
  isLate: { type: Boolean, default: false },
  sweets: { type: Number, default: 0, min: 0, max: 3 },
  markedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
}, { timestamps: true });

export default mongoose.model('Attendance', attendanceSchema);
