import mongoose from 'mongoose';

const updateSchema = new mongoose.Schema({
  platform: {
    type: String,
    required: true,
    enum: ['windows', 'macos', 'android', 'ios'],
    default: 'windows',
    unique: true
  },
  latestVersion: {
    type: String,
    required: true
  },
  latestBuildCode: {
    type: Number,
    required: true
  },
  releaseNotes: {
    type: String,
    default: ''
  },
  downloadUrl: {
    type: String,
    required: true
  },
  createdAt: {
    type: Date,
    default: Date.now
  }
});

const Update = mongoose.model('Update', updateSchema);
export default Update;
