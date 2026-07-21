import mongoose from 'mongoose';
import dotenv from 'dotenv';
dotenv.config();

import Message from './models/Message.js';
import Chat from './models/Chat.js';
import User from './models/User.js';

async function test() {
  await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/jyamiti');
  
  const user = await User.findOne();
  if (!user) {
    console.log("No users found");
    process.exit(0);
  }

  const payload = {
    id: user._id,
    name: user.name,
    email: user.email,
    role: user.role,
    isVerified: user.isVerified
  };

  console.log(JSON.stringify(payload, null, 2));
  process.exit(0);
}

test();
