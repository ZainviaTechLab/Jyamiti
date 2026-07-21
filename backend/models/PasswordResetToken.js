import mongoose from 'mongoose';

const passwordResetTokenSchema = new mongoose.Schema({
  token: { type: String, required: true, unique: true },
  email: { type: String, required: true, lowercase: true },
  expiresAt: { type: Date, required: true },
}, { timestamps: true });

export default mongoose.model('PasswordResetToken', passwordResetTokenSchema);
