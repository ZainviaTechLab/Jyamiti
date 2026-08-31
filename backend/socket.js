import { Server } from 'socket.io';
import { createClient } from 'redis';
import { createAdapter } from '@socket.io/redis-adapter';
import Message from './models/Message.js';
import Chat from './models/Chat.js';
import Competition from './models/Competition.js';
import ClassMeeting from './models/ClassMeeting.js';

let io;

// Compares a student's typed NUMERIC answer against the stored correct
// answer. Both are stored/submitted as strings (correctAnswer can carry a
// decimal), so this parses to Number and allows a tiny epsilon for
// floating-point comparisons rather than doing a brittle string match
// (" 18" vs "18", "18.0" vs "18", etc. should all count as correct).
function numericAnswersMatch(submitted, correct) {
  const a = parseFloat(submitted);
  const b = parseFloat(correct);
  if (Number.isNaN(a) || Number.isNaN(b)) {
    return String(submitted).trim() === String(correct ?? '').trim();
  }
  return Math.abs(a - b) < 1e-9;
}

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

    // ----------------------------------------------------
    // LIVE BATCH COMPETITION ARENA REAL-TIME SOCKET HANDLERS
    // ----------------------------------------------------
    socket.on('competition:host_join', async ({ roomCode }) => {
      try {
        if (!roomCode) return;
        const code = roomCode.toUpperCase();
        socket.join(code);
        console.log(`Tutor host socket joined competition room ${code}`);
      } catch (err) {
        console.error('Error handling competition:host_join', err);
      }
    });

    socket.on('competition:join_room', async ({ roomCode, userId, name, avatar, isHost }) => {
      try {
        const code = roomCode.toUpperCase();
        socket.join(code);

        const competition = await Competition.findOne({ roomCode: code });
        if (!competition) return;

        const uId = String(userId || socket.id);
        const isTutor = isHost || (competition.tutorId && competition.tutorId.toString() === uId) || name === 'Tutor Host';

        // Tutor is the host/observer and should never be added as a player participant
        if (isTutor) {
          console.log(`Tutor (${uId}) connected to room ${code} as Host/Observer (not added as player).`);
          const payload = {
            roomCode: code,
            participants: competition.participants.filter(p => p.userId?.toString() !== competition.tutorId?.toString() && p.name !== 'Tutor Host'),
            status: competition.status
          };
          socket.emit('competition:player_joined', payload);
          return;
        }

        // Add or update participant
        let participant = competition.participants.find(p => p.userId && p.userId.toString() === uId);
        if (!participant) {
          competition.participants.push({
            userId: uId,
            name: name || 'Student',
            avatar: avatar || '',
            totalScore: 0,
            currentRank: competition.participants.length + 1,
            streak: 0,
            responseHistory: []
          });
          await competition.save();
        }

        console.log(`Student ${name} (${uId}) joined competition room ${code}. Total participants: ${competition.participants.length}`);
        
        const payload = {
          roomCode: code,
          participants: competition.participants.filter(p => p.userId?.toString() !== competition.tutorId?.toString() && p.name !== 'Tutor Host'),
          status: competition.status
        };
        io.to(code).emit('competition:player_joined', payload);
        socket.emit('competition:player_joined', payload);
      } catch (err) {
        console.error('Error handling competition:join_room', err);
      }
    });

    socket.on('competition:start_game', async ({ roomCode }) => {
      try {
        const code = roomCode.toUpperCase();
        const competition = await Competition.findOne({ roomCode: code });
        if (!competition || competition.questions.length === 0) return;

        competition.status = 'IN_PROGRESS';
        competition.currentRoundIndex = 0;
        competition.startedAt = new Date();
        await competition.save();

        // Note: correctOptionIndex is included here for MCQ questions (this
        // predates NUMERIC support and isn't fully tamper-proof either way,
        // out of scope to harden here) but NUMERIC questions never send
        // correctAnswer up front -- that would hand the typed answer to
        // anyone glancing at the socket payload before answering.
        const formattedQuestions = competition.questions.map((q, idx) => ({
          id: q.id || `q_${idx}`,
          text: q.text,
          answerType: q.answerType || 'MCQ',
          options: q.options,
          correctOptionIndex: q.answerType === 'NUMERIC' ? undefined : q.correctOptionIndex,
          explanation: q.explanation,
          category: q.category,
          subtopic: q.subtopic
        }));

        const payload = {
          roomCode: code,
          roundIndex: 0,
          totalRounds: competition.questions.length,
          timePerQuestion: competition.timePerQuestion,
          questions: formattedQuestions,
          question: formattedQuestions[0]
        };

        io.to(code).emit('competition:round_started', payload);
        socket.emit('competition:round_started', payload);
      } catch (err) {
        console.error('Error handling competition:start_game', err);
      }
    });

    socket.on('competition:submit_answer', async ({ roomCode, userId, roundIndex, selectedOptionIndex, answerText, timeTakenSec }) => {
      try {
        const code = roomCode.toUpperCase();
        const competition = await Competition.findOne({ roomCode: code });
        if (!competition || competition.status !== 'IN_PROGRESS') return;

        const uId = String(userId || '');
        const participant = competition.participants.find(p => p.userId && p.userId.toString() === uId);
        if (!participant) return;

        const rIdx = roundIndex !== undefined ? parseInt(roundIndex) : participant.responseHistory.length;
        if (competition.questions.length === 0) return;
        const qIndex = rIdx % competition.questions.length;
        const question = competition.questions[qIndex];
        if (!question) return;

        // Check if student already answered this round
        const existingResp = participant.responseHistory.find(r => r.roundIndex === rIdx);
        if (!existingResp) {
          const isNumeric = question.answerType === 'NUMERIC';
          const submittedText = isNumeric ? String(answerText ?? '').trim() : '';
          const isCorrect = isNumeric
            ? submittedText !== '' && numericAnswersMatch(submittedText, question.correctAnswer)
            : (selectedOptionIndex === question.correctOptionIndex);
          let pointsEarned = 0;

          if (isCorrect) {
            participant.streak += 1;
            const streakMultiplier = participant.streak >= 3 ? 1.5 : (participant.streak === 2 ? 1.2 : 1.0);
            const basePoints = 1000;
            const maxTime = competition.timePerQuestion || 30;
            const speedFactor = Math.max(0, (maxTime - (timeTakenSec || 0)) / maxTime);
            const speedBonus = Math.round(500 * speedFactor);
            pointsEarned = Math.round((basePoints + speedBonus) * streakMultiplier);
          } else {
            participant.streak = 0;
          }

          participant.totalScore += pointsEarned;
          participant.responseHistory.push({
            roundIndex: rIdx,
            questionId: question.id,
            selectedOption: isNumeric ? submittedText : (question.options[selectedOptionIndex] || ''),
            isCorrect,
            timeTakenSec: timeTakenSec || 0,
            pointsEarned
          });

          // Update current rank
          competition.participants.sort((a, b) => b.totalScore - a.totalScore);
          competition.participants.forEach((p, idx) => {
            p.currentRank = idx + 1;
          });

          await competition.save();
        }

        // Prepare live progress list for tutor & room
        const participantsProgress = competition.participants.map(p => {
          const roundsCompleted = p.responseHistory ? p.responseHistory.length : 0;
          const correctCount = p.responseHistory ? p.responseHistory.filter(r => r.isCorrect).length : 0;
          const totalAttempted = roundsCompleted;
          const accuracyPct = totalAttempted > 0 ? Math.round((correctCount / totalAttempted) * 100) : 0;
          const totalTimeSec = p.responseHistory ? p.responseHistory.reduce((sum, r) => sum + (r.timeTakenSec || 0), 0) : 0;
          const avgSpeedSec = roundsCompleted > 0 ? parseFloat((totalTimeSec / roundsCompleted).toFixed(1)) : 0;
          const totalRounds = competition.questions.length;
          const progressPct = totalRounds > 0 ? parseFloat((roundsCompleted / totalRounds).toFixed(2)) : 0;

          return {
            userId: p.userId,
            name: p.name,
            avatar: p.avatar,
            totalScore: p.totalScore,
            streak: p.streak,
            currentRank: p.currentRank,
            correctCount,
            totalAttempted,
            accuracyPct,
            roundsCompleted,
            totalRounds,
            progressPct,
            totalTimeSec,
            avgSpeedSec,
            isFinished: roundsCompleted >= totalRounds
          };
        });

        const isAllFinished = competition.participants.length > 0 &&
          competition.participants.every(p => p.responseHistory.length >= competition.questions.length);

        if (isAllFinished) {
          competition.status = 'COMPLETED';
          competition.completedAt = new Date();
          await competition.save();
        }

        const payload = {
          roomCode: code,
          userId: uId,
          participants: participantsProgress,
          isAllFinished,
          status: competition.status
        };

        io.to(code).emit('competition:player_progress', payload);
        socket.emit('competition:player_progress', payload);

        if (isAllFinished) {
          io.to(code).emit('competition:game_over', {
            roomCode: code,
            leaderboard: participantsProgress,
            finalPodium: participantsProgress.slice(0, 3)
          });
        }
      } catch (err) {
        console.error('Error handling competition:submit_answer', err);
      }
    });

    socket.on('competition:end_round', async ({ roomCode }) => {
      try {
        const code = roomCode.toUpperCase();
        const competition = await Competition.findOne({ roomCode: code });
        if (!competition) return;

        competition.status = 'ROUND_RESULT';

        // Update live rankings
        competition.participants.sort((a, b) => b.totalScore - a.totalScore);
        competition.participants.forEach((p, idx) => {
          p.currentRank = idx + 1;
        });

        await competition.save();

        const currentQ = competition.questions[competition.currentRoundIndex];
        const isLastRound = competition.currentRoundIndex >= (competition.questions.length - 1);

        io.to(code).emit('competition:round_ended', {
          roomCode: code,
          roundIndex: competition.currentRoundIndex,
          answerType: currentQ ? (currentQ.answerType || 'MCQ') : 'MCQ',
          correctOptionIndex: currentQ ? currentQ.correctOptionIndex : 0,
          correctAnswer: currentQ && currentQ.answerType === 'NUMERIC' ? currentQ.correctAnswer : undefined,
          explanation: currentQ ? currentQ.explanation : '',
          isLastRound,
          leaderboard: competition.participants.map(p => ({
            userId: p.userId,
            name: p.name,
            avatar: p.avatar,
            totalScore: p.totalScore,
            rank: p.currentRank,
            streak: p.streak
          }))
        });
      } catch (err) {
        console.error('Error handling competition:end_round', err);
      }
    });

    socket.on('competition:next_round', async ({ roomCode }) => {
      try {
        const code = roomCode.toUpperCase();
        const competition = await Competition.findOne({ roomCode: code });
        if (!competition) return;

        const nextRound = competition.currentRoundIndex + 1;
        competition.currentRoundIndex = nextRound;
        competition.status = 'IN_PROGRESS';
        await competition.save();

        const formattedQuestions = competition.questions.map((q, idx) => ({
          id: q.id || `q_${idx}`,
          text: q.text,
          answerType: q.answerType || 'MCQ',
          options: q.options,
          correctOptionIndex: q.answerType === 'NUMERIC' ? undefined : q.correctOptionIndex,
          explanation: q.explanation,
          category: q.category,
          subtopic: q.subtopic
        }));

        const currentQ = formattedQuestions[nextRound % formattedQuestions.length];

        io.to(code).emit('competition:round_started', {
          roomCode: code,
          roundIndex: nextRound,
          totalRounds: competition.questions.length,
          timePerQuestion: competition.timePerQuestion,
          questions: formattedQuestions,
          question: currentQ
        });
      } catch (err) {
        console.error('Error handling competition:next_round', err);
      }
    });

    socket.on('competition:end_game', async ({ roomCode }) => {
      try {
        const code = roomCode.toUpperCase();
        const competition = await Competition.findOne({ roomCode: code });
        if (!competition) return;

        competition.status = 'COMPLETED';
        competition.completedAt = new Date();

        // Compute final ranks
        competition.participants.sort((a, b) => b.totalScore - a.totalScore);
        competition.participants.forEach((p, idx) => {
          p.currentRank = idx + 1;
        });

        await competition.save();

        io.to(code).emit('competition:game_over', {
          roomCode: code,
          competitionId: competition._id,
          finalPodium: competition.participants.slice(0, 3),
          leaderboard: competition.participants
        });
      } catch (err) {
        console.error('Error handling competition:end_game', err);
      }
    });

    // ----------------------------------------------------
    // LIVE CLASS PRESENTATION (Start Class / Join Class room) -- lets the
    // host share slides (and, later, other resource types) with everyone
    // currently in the class. One shared room per meeting (`class_meeting:
    // <meetingId>`), mirroring the competition-arena room pattern above:
    // the host's navigation actions persist the new state onto the
    // ClassMeeting document and broadcast it to the whole room; a student
    // joining the room gets the CURRENT state read back immediately so a
    // late join or reconnect doesn't have to wait for the host's next move.
    // ----------------------------------------------------
    socket.on('class_meeting:join_room', async ({ meetingId }) => {
      try {
        if (!meetingId) return;
        socket.join(`class_meeting:${meetingId}`);

        const meeting = await ClassMeeting.findById(meetingId).select('presentedContent');
        socket.emit('class_meeting:presentation_update', {
          meetingId,
          presentedContent: meeting?.presentedContent || null,
        });
      } catch (err) {
        console.error('Error handling class_meeting:join_room', err);
      }
    });

    socket.on(
      'class_meeting:present_slide',
      async ({ meetingId, hostId, deckId, deckTitle, slideIndex, totalSlides }) => {
        try {
          if (!meetingId) return;
          const meeting = await ClassMeeting.findById(meetingId);
          if (!meeting) return;
          // Only the actual host may drive the presentation. Same trust
          // level as the rest of this file -- client-declared ids, no
          // per-socket JWT verification anywhere else here either -- but
          // still checked against the persisted hostId rather than trusted
          // blindly, matching the REST /:id/end route's own check.
          if (String(meeting.hostId) !== String(hostId)) return;

          meeting.presentedContent = {
            kind: 'slide',
            deckId: deckId || null,
            deckTitle: deckTitle || null,
            slideIndex: slideIndex || 0,
            totalSlides: totalSlides || 0,
          };
          await meeting.save();

          io.to(`class_meeting:${meetingId}`).emit('class_meeting:presentation_update', {
            meetingId,
            presentedContent: meeting.presentedContent,
          });
        } catch (err) {
          console.error('Error handling class_meeting:present_slide', err);
        }
      }
    );

    socket.on('class_meeting:stop_presenting', async ({ meetingId, hostId }) => {
      try {
        if (!meetingId) return;
        const meeting = await ClassMeeting.findById(meetingId);
        if (!meeting) return;
        if (String(meeting.hostId) !== String(hostId)) return;

        meeting.presentedContent = {
          kind: null,
          deckId: null,
          deckTitle: null,
          slideIndex: 0,
          totalSlides: 0,
        };
        await meeting.save();

        io.to(`class_meeting:${meetingId}`).emit('class_meeting:presentation_update', {
          meetingId,
          presentedContent: null,
        });
      } catch (err) {
        console.error('Error handling class_meeting:stop_presenting', err);
      }
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
