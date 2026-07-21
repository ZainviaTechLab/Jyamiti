import Chat from '../models/Chat.js';
import Message from '../models/Message.js';
import User from '../models/User.js';
import Batch from '../models/Batch.js';

// Get all chats for the logged in user
export const fetchChats = async (req, res) => {
  try {
    const userId = req.user.id || req.user._id;

    // First, ensure the rule engine applies (students have chats with their tutor, mentor, admin, and batch group)
    if (req.user.role === 'STUDENT') {
      await autoProvisionChatsForStudent(userId);
    } else if (req.user.role === 'TUTOR') {
      await autoProvisionChatsForTutor(userId);
    } else if (req.user.role === 'MENTOR') {
      await autoProvisionChatsForMentor(userId);
    } else if (req.user.role === 'ADMIN') {
      await autoProvisionChatsForAdmin(userId);
    }

    const chats = await Chat.find({ participants: userId })
      .populate('participants', '-password')
      .populate('latestMessage')
      .populate('batch', 'name')
      .sort({ updatedAt: -1 });

    res.status(200).json(chats);
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch chats', error: error.message });
  }
};

// Auto-provision logic for students
const autoProvisionChatsForStudent = async (studentId) => {
  const student = await User.findById(studentId);
  const batches = await Batch.find({ students: studentId }).populate('tutor mentors');

  // Find all admins
  const admins = await User.find({ role: 'ADMIN' });

  // 1. Create direct chat with all Admins
  for (const admin of admins) {
    await ensureDirectChatExists(studentId, admin._id);
  }

  // 2. Create direct chat with Tutors and Mentors of enrolled batches
  for (const batch of batches) {
    if (batch.tutor) await ensureDirectChatExists(studentId, batch.tutor._id);
    if (batch.mentors && batch.mentors.length > 0) {
      for (const mentor of batch.mentors) {
        await ensureDirectChatExists(studentId, mentor._id);
      }
    }

    // 3. Ensure student is in the Batch Group Chat
    await ensureBatchGroupChat(batch, studentId);
  }
};

const autoProvisionChatsForTutor = async (tutorId) => {
  const batches = await Batch.find({ tutor: tutorId }).populate('students');
  
  for (const batch of batches) {
    for (const student of batch.students) {
      await ensureDirectChatExists(tutorId, student._id);
    }
    await ensureBatchGroupChat(batch, tutorId);
  }
};

const autoProvisionChatsForMentor = async (mentorId) => {
  const batches = await Batch.find({ mentors: mentorId }).populate('students');
  
  for (const batch of batches) {
    for (const student of batch.students) {
      await ensureDirectChatExists(mentorId, student._id);
    }
    await ensureBatchGroupChat(batch, mentorId);
  }
};

const autoProvisionChatsForAdmin = async (adminId) => {
  const allUsers = await User.find({ _id: { $ne: adminId } });
  for (const user of allUsers) {
    await ensureDirectChatExists(adminId, user._id);
  }
  
  const allBatches = await Batch.find({});
  for (const batch of allBatches) {
    await ensureBatchGroupChat(batch, adminId);
  }
};

const ensureDirectChatExists = async (user1, user2) => {
  const existingChat = await Chat.findOne({
    type: 'direct',
    participants: { $all: [user1, user2], $size: 2 }
  });

  if (!existingChat) {
    await Chat.create({
      type: 'direct',
      participants: [user1, user2],
      unreadCounts: {
        [user1.toString()]: 0,
        [user2.toString()]: 0
      }
    });
  }
};

const ensureBatchGroupChat = async (batch, studentId) => {
  let groupChat = await Chat.findOne({ type: 'group', batch: batch._id });

  if (!groupChat) {
    const initialParticipants = [batch.tutor?._id, ...(batch.mentors?.map(m => m._id) || [])].filter(Boolean);
    groupChat = await Chat.create({
      type: 'group',
      name: batch.name,
      batch: batch._id,
      participants: initialParticipants
    });
  }

  if (!groupChat.participants.includes(studentId)) {
    groupChat.participants.push(studentId);
    groupChat.unreadCounts.set(studentId.toString(), 0);
    groupChat.markModified('unreadCounts');
    await groupChat.save();
  }
};

// Get all messages for a specific chat
export const fetchMessages = async (req, res) => {
  try {
    const { chatId } = req.params;
    
    // Mark as read for this user
    const chat = await Chat.findById(chatId);
    if (!chat) return res.status(404).json({ message: 'Chat not found' });

    const userId = req.user.id || req.user._id;
    chat.unreadCounts.set(userId.toString(), 0);
    chat.markModified('unreadCounts');
    await chat.save();

    const messages = await Message.find({ chat: chatId })
      .populate('sender', 'name role email')
      .sort({ createdAt: 1 }); // Oldest to newest for rendering

    res.status(200).json(messages);
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch messages', error: error.message });
  }
};
