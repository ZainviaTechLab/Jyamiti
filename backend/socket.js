import { Server } from 'socket.io';
import { createClient } from 'redis';
import { createAdapter } from '@socket.io/redis-adapter';
import Message from './models/Message.js';
import Chat from './models/Chat.js';

let io;

export const initSocket = async (httpServer) => {
  io = new Server(httpServer, {
    cors: {
      origin: "*", // Adjust in production
      methods: ["GET", "POST"]
    }
  });

  try {
    const redisOptions = { 
      url: process.env.REDIS_URL || 'redis://localhost:6379',
      socket: { reconnectStrategy: false } // Do not spam retries if Redis isn't running
    };
    
    const pubClient = createClient(redisOptions);
    const subClient = pubClient.duplicate();

    pubClient.on('error', () => {}); // Suppress default error logs since we catch it below
    subClient.on('error', () => {});

    await Promise.all([pubClient.connect(), subClient.connect()]);
    io.adapter(createAdapter(pubClient, subClient));
    console.log('Socket.io Redis adapter configured successfully');
  } catch (error) {
    console.warn('Could not connect to Redis. Falling back to in-memory adapter.');
  }

  io.on('connection', (socket) => {
    console.log('User connected to socket:', socket.id);

    // Join personal room for user-specific notifications
    socket.on('setup', (userId) => {
      socket.join(userId);
      console.log('User joined personal room:', userId);
    });

    // Join specific chat room
    socket.on('join_chat', (chatId) => {
      socket.join(chatId);
      console.log('User joined chat:', chatId);
    });

    // Handle new message
    socket.on('new_message', async (messageData) => {
      const { chatId, senderId, content } = messageData;
      
      try {
        // Find chat to get participants
        const chat = await Chat.findById(chatId).populate('participants', '_id');
        if (!chat) return;

        // Create new message in DB
        const newMessage = await Message.create({
          chat: chatId,
          sender: senderId,
          content: content,
          readBy: [senderId]
        });

        const populatedMessage = await Message.findById(newMessage._id)
          .populate('sender', 'name role email');

        // Update latest message and unread counts in chat
        chat.latestMessage = newMessage._id;
        
        chat.participants.forEach(participant => {
          const pid = participant._id.toString();
          if (pid !== senderId) {
            const currentCount = chat.unreadCounts.get(pid) || 0;
            chat.unreadCounts.set(pid, currentCount + 1);
          }
        });
        
        chat.markModified('unreadCounts');
        await chat.save();

        // Broadcast to everyone in the chat room
        io.to(chatId).emit('message_received', populatedMessage);

        // Also emit a notification to the users directly if they aren't in the chat room
        chat.participants.forEach(participant => {
          const pid = participant._id.toString();
          if (pid !== senderId) {
             socket.in(pid).emit('new_message_notification', {
                chatId: chatId,
                message: populatedMessage
             });
          }
        });

      } catch (error) {
        console.error('Error handling new message:', error);
      }
    });

    socket.on('typing', (data) => {
      socket.in(data.chatId).emit('typing', data);
    });

    socket.on('stop_typing', (data) => {
      socket.in(data.chatId).emit('stop_typing', data);
    });

    socket.on('disconnect', () => {
      console.log('User disconnected from socket:', socket.id);
    });
  });
};

export const getIO = () => {
  if (!io) throw new Error('Socket.io not initialized!');
  return io;
};
