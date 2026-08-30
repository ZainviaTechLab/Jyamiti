import express from 'express';
import mongoose from 'mongoose';
import Competition from '../models/Competition.js';
import Batch from '../models/Batch.js';
import AssessmentQuestion from '../models/AssessmentQuestion.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';
import { getIO } from '../socket.js';

const router = express.Router();

// Helper to generate a unique 6-character room code (e.g. JYAM-92)
function generateRoomCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = 'JYAM-';
  for (let i = 0; i < 4; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// Helper to extract practice questions from course syllabus by selected topic titles
function extractQuestionsFromCourseSyllabus(course, selectedTopics = []) {
  const extracted = [];
  if (!course || !course.syllabus) return extracted;

  const topicsFilter = (selectedTopics && selectedTopics.length > 0)
    ? selectedTopics.map(t => t.trim().toLowerCase())
    : null;

  course.syllabus.forEach(chapter => {
    const chapterMatch = !topicsFilter || topicsFilter.includes((chapter.title || '').trim().toLowerCase());

    // Questions directly in chapter
    if (chapterMatch && chapter.practiceQuestions && chapter.practiceQuestions.length > 0) {
      chapter.practiceQuestions.forEach(q => {
        if (q.text && q.options && q.options.length > 0) {
          extracted.push({
            id: q._id ? q._id.toString() : `q_${Date.now()}_${Math.random()}`,
            text: q.text,
            options: q.options.map(o => o.text || o || ''),
            correctOptionIndex: q.correctAnswers && q.correctAnswers.length > 0
              ? Math.max(0, q.options.findIndex(o => (o.text || o) === q.correctAnswers[0]))
              : 0,
            explanation: q.descriptiveText || '',
            category: chapter.title || 'Mathematics',
            subtopic: '',
            points: 1000
          });
        }
      });
    }

    if (chapter.topics) {
      chapter.topics.forEach(topic => {
        const topicMatch = chapterMatch || (!topicsFilter || topicsFilter.includes((topic.title || '').trim().toLowerCase()));
        
        if (topicMatch && topic.practiceQuestions && topic.practiceQuestions.length > 0) {
          topic.practiceQuestions.forEach(q => {
            if (q.text && q.options && q.options.length > 0) {
              extracted.push({
                id: q._id ? q._id.toString() : `q_${Date.now()}_${Math.random()}`,
                text: q.text,
                options: q.options.map(o => o.text || o || ''),
                correctOptionIndex: q.correctAnswers && q.correctAnswers.length > 0
                  ? Math.max(0, q.options.findIndex(o => (o.text || o) === q.correctAnswers[0]))
                  : 0,
                explanation: q.descriptiveText || '',
                category: topic.title || chapter.title || 'Mathematics',
                subtopic: '',
                points: 1000
              });
            }
          });
        }

        if (topic.subTopics) {
          topic.subTopics.forEach(sub => {
            const subMatch = topicMatch || (!topicsFilter || topicsFilter.includes((sub.title || '').trim().toLowerCase()));
            if (subMatch && sub.practiceQuestions && sub.practiceQuestions.length > 0) {
              sub.practiceQuestions.forEach(q => {
                if (q.text && q.options && q.options.length > 0) {
                  extracted.push({
                    id: q._id ? q._id.toString() : `q_${Date.now()}_${Math.random()}`,
                    text: q.text,
                    options: q.options.map(o => o.text || o || ''),
                    correctOptionIndex: q.correctAnswers && q.correctAnswers.length > 0
                      ? Math.max(0, q.options.findIndex(o => (o.text || o) === q.correctAnswers[0]))
                      : 0,
                    explanation: q.descriptiveText || '',
                    category: topic.title || chapter.title || 'Mathematics',
                    subtopic: sub.title || '',
                    points: 1000
                  });
                }
              });
            }
          });
        }
      });
    }
  });

  return extracted;
}

// 0. Fetch structured curriculum chapters and topics for a batch's course
router.get('/batch/:batchId/topics', authenticateToken, async (req, res) => {
  try {
    const batch = await Batch.findById(req.params.batchId).populate('course');
    if (!batch) {
      return res.status(404).json({ message: 'Batch not found.' });
    }

    const chaptersMap = new Map(); // Chapter Title -> Set of Topics
    let courseName = '';

    if (batch.course) {
      courseName = batch.course.name || '';
      if (batch.course.syllabus && Array.isArray(batch.course.syllabus)) {
        batch.course.syllabus.forEach(ch => {
          const chapTitle = (ch.title || 'General Curriculum').trim();
          if (!chaptersMap.has(chapTitle)) {
            chaptersMap.set(chapTitle, new Set());
          }

          if (ch.topics && Array.isArray(ch.topics)) {
            ch.topics.forEach(t => {
              if (t.title) chaptersMap.get(chapTitle).add(t.title.trim());
              if (t.subTopics && Array.isArray(t.subTopics)) {
                t.subTopics.forEach(st => {
                  if (st.title) chaptersMap.get(chapTitle).add(st.title.trim());
                });
              }
            });
          }
        });
      }
    }

    // Also group distinct categories from AssessmentQuestion bank under Assessment Bank chapter
    const bankTopics = await AssessmentQuestion.distinct('category', { grade: batch.grade || 10 });
    if (bankTopics.length > 0) {
      const bankChap = 'Assessment Question Bank';
      if (!chaptersMap.has(bankChap)) {
        chaptersMap.set(bankChap, new Set());
      }
      bankTopics.forEach(bt => {
        if (bt && bt.trim()) chaptersMap.get(bankChap).add(bt.trim());
      });
    }

    // Format response
    const chaptersList = [];
    chaptersMap.forEach((topicsSet, chapTitle) => {
      chaptersList.push({
        title: chapTitle,
        topics: Array.from(topicsSet).sort()
      });
    });

    res.json({
      chapters: chaptersList,
      courseName,
      grade: batch.grade || 10
    });
  } catch (error) {
    console.error('Error fetching batch chapters & topics:', error);
    res.status(500).json({ message: 'Server error.', error: error.message });
  }
});

// 1. Create a new Live Competition Arena Room
router.post('/create', authenticateToken, requireRole(['tutor', 'admin']), async (req, res) => {
  try {
    const { title, batchId, grade, timePerQuestion, numberOfRounds, roundDurationMinutes, selectedTopics, questionCount, questions, mode } = req.body;

    if (!title || !batchId) {
      return res.status(400).json({ message: 'Title and batchId are required.' });
    }

    const rounds = parseInt(numberOfRounds) || parseInt(questionCount) || 3;
    const durationMinutes = parseInt(roundDurationMinutes) || (timePerQuestion ? Math.max(1, Math.round(timePerQuestion / 60)) : 1);
    const calculatedTimePerQuestion = durationMinutes * 60; // duration in seconds per round
    const targetCount = rounds; // Number of questions = Number of rounds

    // Generate unique room code
    let roomCode = generateRoomCode();
    let existing = await Competition.findOne({ roomCode, status: { $ne: 'COMPLETED' } });
    while (existing) {
      roomCode = generateRoomCode();
      existing = await Competition.findOne({ roomCode, status: { $ne: 'COMPLETED' } });
    }

    // Prepare questions list
    let formattedQuestions = [];
    if (questions && Array.isArray(questions) && questions.length > 0) {
      formattedQuestions = questions.map((q, idx) => {
        const isNumeric = q.answerType === 'NUMERIC';
        return {
          id: q.id || `q_${idx}_${Date.now()}`,
          text: q.text || q.questionText || 'Solve the equation',
          answerType: isNumeric ? 'NUMERIC' : 'MCQ',
          options: isNumeric ? [] : (q.options || q.choices || ['Option A', 'Option B', 'Option C', 'Option D']),
          correctOptionIndex: isNumeric
            ? undefined
            : (q.correctOptionIndex !== undefined ? q.correctOptionIndex : (q.correctAnswerIndex || 0)),
          correctAnswer: isNumeric ? String(q.correctAnswer ?? '') : undefined,
          explanation: q.explanation || '',
          category: q.category || q.topic || 'Mathematics',
          subtopic: q.subtopic || '',
          points: q.points || 1000
        };
      });
    } else {
      // 1. Fetch practice questions from course syllabus matching selected topics
      const batch = await Batch.findById(batchId).populate('course');
      let candidates = [];

      if (batch && batch.course) {
        candidates = extractQuestionsFromCourseSyllabus(batch.course, selectedTopics);
      }

      // 2. Supplement with AssessmentQuestion bank if candidate pool is small
      let queryFilter = { grade: grade || 10 };
      if (selectedTopics && Array.isArray(selectedTopics) && selectedTopics.length > 0) {
        queryFilter.$or = [
          { category: { $in: selectedTopics } },
          { subtopic: { $in: selectedTopics } }
        ];
      }

      const bankQuestions = await AssessmentQuestion.find(queryFilter).limit(targetCount * 2);
      bankQuestions.forEach(sq => {
        candidates.push({
          id: sq._id.toString(),
          text: sq.text,
          options: sq.options.map(o => o.text || ''),
          correctOptionIndex: sq.options.findIndex(o => o.isCorrect) >= 0 ? sq.options.findIndex(o => o.isCorrect) : 0,
          explanation: sq.explanation || '',
          category: sq.category || 'Mathematics',
          subtopic: sq.subtopic || '',
          points: 1000
        });
      });

      // 3. Fallback: general assessment questions for the grade if candidates still empty
      if (candidates.length === 0) {
        const fallbackQuestions = await AssessmentQuestion.find({ grade: grade || 10 }).limit(targetCount);
        candidates = fallbackQuestions.map(sq => ({
          id: sq._id.toString(),
          text: sq.text,
          options: sq.options.map(o => o.text || ''),
          correctOptionIndex: sq.options.findIndex(o => o.isCorrect) >= 0 ? sq.options.findIndex(o => o.isCorrect) : 0,
          explanation: sq.explanation || '',
          category: sq.category || 'Mathematics',
          subtopic: sq.subtopic || '',
          points: 1000
        }));
      }

      // Shuffle candidate questions and slice to targetCount
      candidates.sort(() => 0.5 - Math.random());
      formattedQuestions = candidates.slice(0, targetCount);

      // Bulletproof Fallback: Auto-generate high-quality Grade 10 Math Arena Questions if pool is small
      if (formattedQuestions.length < targetCount) {
        const mathFallbacks = [
          { text: "Solve for $x$: $2x + 5 = 15$", options: ["$x = 5$", "$x = 10$", "$x = 7.5$", "$x = 4$"], correctOptionIndex: 0, category: "Algebra", explanation: "$2x = 10 \\implies x = 5$" },
          { text: "Find the area of a circle with radius $r = 7\\text{ cm}$. (Use $\\pi = \\frac{22}{7}$)", options: ["$154\\text{ cm}^2$", "$44\\text{ cm}^2$", "$144\\text{ cm}^2$", "$49\\text{ cm}^2$"], correctOptionIndex: 0, category: "Geometry", explanation: "$\\text{Area} = \\pi r^2 = \\frac{22}{7} \\times 49 = 154\\text{ cm}^2$" },
          { text: "What is the value of $\\sin(30^\\circ) + \\cos(60^\\circ)$?", options: ["$1$", "$\\frac{1}{2}$", "$\\sqrt{3}$", "$\\frac{\\sqrt{3}}{2}$"], correctOptionIndex: 0, category: "Trigonometry", explanation: "$\\sin(30^\\circ) = 0.5, \\cos(60^\\circ) = 0.5 \\implies 0.5 + 0.5 = 1$" },
          { text: "If the roots of $x^2 - 5x + 6 = 0$ are $\\alpha$ and $\\beta$, find $\\alpha + \\beta$.", options: ["$5$", "$6$", "$-5$", "$-6$"], correctOptionIndex: 0, category: "Quadratic Equations", explanation: "Sum of roots $= -b/a = -(-5)/1 = 5$" },
          { text: "Find the $10^{\\text{th}}$ term of the AP: $2, 7, 12, 17, \\dots$", options: ["$47$", "$42$", "$52$", "$50$"], correctOptionIndex: 0, category: "Arithmetic Progressions", explanation: "$a_{10} = a + 9d = 2 + 9(5) = 47$" }
        ];

        while (formattedQuestions.length < targetCount) {
          const fb = mathFallbacks[formattedQuestions.length % mathFallbacks.length];
          formattedQuestions.push({
            id: `q_fallback_${formattedQuestions.length}_${Date.now()}`,
            text: fb.text,
            options: fb.options,
            correctOptionIndex: fb.correctOptionIndex,
            explanation: fb.explanation,
            category: fb.category,
            subtopic: '',
            points: 1000
          });
        }
      }
    }

    if (formattedQuestions.length === 0) {
      return res.status(400).json({ message: 'No valid questions found for the selected topics. Try selecting different topics.' });
    }

    const competition = new Competition({
      roomCode,
      title,
      batchId,
      tutorId: req.user.id,
      grade: grade || 10,
      mode: mode === 'MATH_FUNDAMENTALS' ? 'MATH_FUNDAMENTALS' : 'SYLLABUS',
      numberOfRounds: rounds,
      roundDurationMinutes: durationMinutes,
      timePerQuestion: calculatedTimePerQuestion,
      questions: formattedQuestions,
      status: 'LOBBY',
      participants: []
    });

    await competition.save();

    res.status(201).json({
      message: 'Competition room created successfully.',
      competition
    });
  } catch (error) {
    console.error('Error creating competition:', error);
    res.status(500).json({ message: 'Failed to create competition room.', error: error.message });
  }
});

// 2. Fetch competition room by Room Code (for student joining verification)
router.get('/room/:roomCode', authenticateToken, async (req, res) => {
  try {
    const roomCode = req.params.roomCode.toUpperCase();
    const competition = await Competition.findOne({ roomCode }).populate('tutorId', 'name avatar');

    if (!competition) {
      return res.status(404).json({ message: 'Competition room not found. Check your Room Code.' });
    }

    res.json({ competition });
  } catch (error) {
    console.error('Error fetching competition room:', error);
    res.status(500).json({ message: 'Server error.', error: error.message });
  }
});

// 2b. Join competition room via HTTP endpoint
router.post('/join', authenticateToken, async (req, res) => {
  try {
    const { roomCode, name, avatar } = req.body;
    if (!roomCode) return res.status(400).json({ message: 'roomCode is required.' });

    const code = roomCode.toUpperCase();
    const competition = await Competition.findOne({ roomCode: code });
    if (!competition) return res.status(404).json({ message: 'Competition room not found.' });

    const userId = String(req.user.id);
    let participant = competition.participants.find(p => p.userId && p.userId.toString() === userId);
    if (!participant) {
      competition.participants.push({
        userId,
        name: name || req.user.name || 'Student',
        avatar: avatar || req.user.avatar || '',
        totalScore: 0,
        currentRank: competition.participants.length + 1,
        streak: 0,
        responseHistory: []
      });
      await competition.save();
    }

    // Broadcast update via Socket.IO
    try {
      const io = getIO();
      io.to(code).emit('competition:player_joined', {
        roomCode: code,
        participants: competition.participants,
        status: competition.status
      });
    } catch (e) {
      console.warn('Socket emit error on HTTP join:', e.message);
    }

    res.json({ message: 'Joined competition successfully.', competition });
  } catch (error) {
    console.error('Error joining competition:', error);
    res.status(500).json({ message: 'Server error.', error: error.message });
  }
});

// 2c. Start competition via HTTP endpoint
router.post('/start', authenticateToken, requireRole(['tutor', 'admin']), async (req, res) => {
  try {
    const { roomCode } = req.body;
    if (!roomCode) return res.status(400).json({ message: 'roomCode is required.' });

    const code = roomCode.toUpperCase();
    const competition = await Competition.findOne({ roomCode: code });
    if (!competition || !competition.questions || competition.questions.length === 0) {
      return res.status(404).json({ message: 'Competition or questions not found.' });
    }

    competition.status = 'IN_PROGRESS';
    competition.currentRoundIndex = 0;
    competition.startedAt = new Date();
    await competition.save();

    const firstQ = competition.questions[0];
    const payload = {
      roomCode: code,
      roundIndex: 0,
      totalRounds: competition.questions.length,
      timePerQuestion: competition.timePerQuestion,
      question: {
        id: firstQ.id || 'q_0',
        text: firstQ.text,
        options: firstQ.options,
        category: firstQ.category,
        subtopic: firstQ.subtopic
      }
    };

    try {
      const io = getIO();
      io.to(code).emit('competition:round_started', payload);
    } catch (e) {
      console.warn('Socket emit error on start competition:', e.message);
    }

    res.json({ message: 'Competition started successfully.', competition });
  } catch (error) {
    console.error('Error starting competition:', error);
    res.status(500).json({ message: 'Server error.', error: error.message });
  }
});

// 3. List active & past competitions for a Batch
router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const competitions = await Competition.find({ batchId: req.params.batchId })
      .sort({ createdAt: -1 })
      .populate('tutorId', 'name');

    res.json({ competitions });
  } catch (error) {
    console.error('Error fetching batch competitions:', error);
    res.status(500).json({ message: 'Server error.', error: error.message });
  }
});

// 4. Detailed Post-Game Analytics & Weak/Strong Points Analysis
router.get('/:id/analytics', authenticateToken, async (req, res) => {
  try {
    let competition;
    const targetId = req.params.id;

    if (mongoose.Types.ObjectId.isValid(targetId)) {
      competition = await Competition.findById(targetId)
        .populate('batchId', 'name')
        .populate('tutorId', 'name')
        .populate('participants.userId', 'name avatar email');
    }

    if (!competition) {
      competition = await Competition.findOne({ roomCode: targetId.toUpperCase() })
        .populate('batchId', 'name')
        .populate('tutorId', 'name')
        .populate('participants.userId', 'name avatar email');
    }

    if (!competition) {
      return res.status(404).json({ message: 'Competition not found.' });
    }

    // Compute Weak & Strong points per topic
    const topicStats = {};
    let totalResponses = 0;
    let totalCorrectResponses = 0;

    competition.questions.forEach((q) => {
      const topic = q.category || 'General Math';
      if (!topicStats[topic]) {
        topicStats[topic] = { total: 0, correct: 0, timeTakenSecSum: 0 };
      }
    });

    competition.participants.forEach((p) => {
      p.responseHistory.forEach((resp) => {
        const qIndex = resp.roundIndex;
        if (qIndex < competition.questions.length) {
          const q = competition.questions[qIndex];
          const topic = q.category || 'General Math';

          if (!topicStats[topic]) {
            topicStats[topic] = { total: 0, correct: 0, timeTakenSecSum: 0 };
          }

          topicStats[topic].total += 1;
          if (resp.isCorrect) {
            topicStats[topic].correct += 1;
            totalCorrectResponses += 1;
          }
          topicStats[topic].timeTakenSecSum += (resp.timeTakenSec || 0);
          totalResponses += 1;
        }
      });
    });

    const topicPerformance = Object.keys(topicStats).map(topic => {
      const stat = topicStats[topic];
      const accuracyPct = stat.total > 0 ? Math.round((stat.correct / stat.total) * 100) : 0;
      const avgTimeSec = stat.total > 0 ? Math.round((stat.timeTakenSecSum / stat.total) * 10) / 10 : 0;
      return {
        topic,
        totalQuestions: stat.total,
        correctCount: stat.correct,
        accuracyPct,
        avgTimeSec,
        masteryLevel: accuracyPct >= 75 ? 'STRONG' : (accuracyPct >= 50 ? 'MODERATE' : 'WEAK')
      };
    });

    // Sort participants by totalScore descending
    const sortedParticipants = [...competition.participants].sort((a, b) => b.totalScore - a.totalScore);

    res.json({
      competitionId: competition._id,
      roomCode: competition.roomCode,
      title: competition.title,
      batchName: competition.batchId ? competition.batchId.name : 'Batch',
      totalParticipants: competition.participants.length,
      totalRounds: competition.questions.length,
      overallAccuracyPct: totalResponses > 0 ? Math.round((totalCorrectResponses / totalResponses) * 100) : 0,
      topicPerformance,
      leaderboard: sortedParticipants,
      questions: competition.questions
    });
  } catch (error) {
    console.error('Error generating competition analytics:', error);
    res.status(500).json({ message: 'Failed to generate analytics.', error: error.message });
  }
});

export default router;
