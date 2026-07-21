import mongoose from 'mongoose';

const paymentSchema = new mongoose.Schema({
  student: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  batch: { type: mongoose.Schema.Types.ObjectId, ref: 'Batch', required: true },
  monthYear: { type: String, required: true }, // Format: YYYY-MM
  sessionsCount: { type: Number, required: true },
  feePerSession: { type: Number, required: true },
  amountDue: { type: Number, required: true },
  status: { type: String, enum: ['PENDING', 'PAID'], default: 'PENDING' },
  dueDate: { type: Date, required: true },
  paidAt: { type: Date }
}, { timestamps: true });

// Prevent duplicate payment records for the same student/batch/month
paymentSchema.index({ student: 1, batch: 1, monthYear: 1 }, { unique: true });

export default mongoose.model('Payment', paymentSchema);
