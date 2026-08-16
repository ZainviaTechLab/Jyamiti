import mongoose from 'mongoose';

const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true },
  phone: { type: String, required: false },
  role: { type: String, enum: ['ADMIN', 'TUTOR', 'MENTOR', 'STUDENT'], required: true },
  isActive: { type: Boolean, default: true },
  status: { type: String, enum: ['ACTIVE', 'INACTIVE', 'SUSPENDED'], default: 'ACTIVE' },
  isProfileComplete: { type: Boolean, default: false },
  bio: { type: String, required: false },
  qualifications: { type: String, required: false },
  experienceYears: { type: Number, required: false },
}, { timestamps: true });

export default mongoose.model('User', userSchema);
