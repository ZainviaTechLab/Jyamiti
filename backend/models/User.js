import mongoose from 'mongoose';

const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true },
  password: { type: String, required: true },
  phone: { type: String, required: false },
  role: { type: String, enum: ['ADMIN', 'TUTOR', 'MENTOR', 'STUDENT'], required: true },
}, { timestamps: true });

export default mongoose.model('User', userSchema);
