import mongoose from 'mongoose';

const batchCategorySchema = new mongoose.Schema({
  name: { type: String, required: true, unique: true },
  maxMembers: { type: Number, required: true },
  fees: { type: Number, required: true }
}, { timestamps: true });

export default mongoose.model('BatchCategory', batchCategorySchema);
