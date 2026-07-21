import mongoose from 'mongoose';
import dotenv from 'dotenv';
dotenv.config();
import Message from './models/Message.js';
import User from './models/User.js';

async function test() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/jyamiti');
  
  const msg = await Message.findOne().populate('sender', 'name role email');
  if (!msg) {
    console.log("No messages");
    process.exit();
  }

  // Simulate express json output
  console.log(JSON.stringify(msg.toJSON(), null, 2));
  process.exit();
}
test();
