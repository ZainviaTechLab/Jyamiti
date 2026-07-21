import express from 'express';
import Exam from '../models/Exam.js';
import ExamSubmission from '../models/ExamSubmission.js';
import Question from '../models/Question.js';
import Batch from '../models/Batch.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

router.get('/batch/:batchId', authenticateToken, async (req, res) => {
  try {
    const exams = await Exam.find({ batch: req.params.batchId }).populate('questions').sort({ createdAt: -1 });
    
    if (req.user.role === 'STUDENT') {
      const examIds = exams.map(e => e._id);
      const submissions = await ExamSubmission.find({ student: req.user.id, exam: { $in: examIds } }, 'exam');
      const submittedExamIds = submissions.map(s => s.exam.toString());
      
      const examsWithStatus = exams.map(e => {
        const examObj = e.toObject();
        // remove correctAnswers so students can't cheat by looking at the list
        examObj.questions.forEach(q => delete q.correctAnswers);
        return {
          ...examObj,
          hasSubmitted: submittedExamIds.includes(e._id.toString())
        };
      });
      return res.json(examsWithStatus);
    }
    
    res.json(exams);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.post('/', authenticateToken, requireRole(['TUTOR']), async (req, res) => {
  try {
    const { title, description, batch, questions, duration } = req.body;
    const exam = await Exam.create({ title, description, batch, questions, duration, tutor: req.user.id });
    res.status(201).json(exam);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.put('/:id', authenticateToken, requireRole(['TUTOR']), async (req, res) => {
  try {
    const { title, description, duration, questions } = req.body;
    const exam = await Exam.findByIdAndUpdate(
      req.params.id,
      { title, description, duration, questions },
      { new: true }
    );
    if (!exam) return res.status(404).json({ message: 'Exam not found' });
    res.json(exam);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/performance', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const submissions = await ExamSubmission.find({ student: req.user.id, status: 'GRADED' })
      .populate({
        path: 'exam',
        populate: [
          { path: 'batch', select: 'name' },
          { path: 'questions', select: 'marks chapter topic' }
        ]
      })
      .populate('student', 'name email');

    if (!submissions || submissions.length === 0) {
      const user = await req.user;
      return res.json({ 
        student: { id: user.id, name: user.name || 'Student' }, 
        subjects: [], 
        overall: {}, 
        summary: {} 
      });
    }

    const studentData = {
      id: submissions[0].student._id,
      name: submissions[0].student.name,
      username: submissions[0].student.email,
    };

    const chaptersMap = {};
    let totalExams = 0;
    let totalQuestionsAll = 0;
    let totalMarksAll = 0;
    let marksObtainedAll = 0;

    submissions.forEach(sub => {
      const exam = sub.exam;
      if (!exam) return;
      
      totalExams += 1;
      
      sub.answers.forEach(ans => {
        const question = exam.questions.find(q => q._id.toString() === ans.questionId.toString());
        if (!question) return;
        
        const chapter = question.chapter || 'Uncategorized';
        const topic = question.topic || 'General';
        
        if (!chaptersMap[chapter]) {
          chaptersMap[chapter] = {
            subject: chapter,
            subject_display: chapter,
            total_exams: 0,
            total_marks: 0,
            marks_obtained: 0,
            online_exams: 0,
            offline_exams: 0,
            combined_score: 0,
            performance_rating: 'Not Rated',
            topicsMap: {},
            examSet: new Set()
          };
        }
        
        const chapStats = chaptersMap[chapter];
        chapStats.examSet.add(exam._id.toString());
        chapStats.total_marks += (question.marks || 1);
        chapStats.marks_obtained += (ans.marksObtained || 0);
        
        if (!chapStats.topicsMap[topic]) {
          chapStats.topicsMap[topic] = {
            topic: topic,
            total_marks: 0,
            marks_obtained: 0
          };
        }
        
        chapStats.topicsMap[topic].total_marks += (question.marks || 1);
        chapStats.topicsMap[topic].marks_obtained += (ans.marksObtained || 0);
        
        totalMarksAll += (question.marks || 1);
        marksObtainedAll += (ans.marksObtained || 0);
        totalQuestionsAll += 1;
      });
    });

    const getRating = (percentage) => {
      if (percentage >= 85) return 'Excellent';
      if (percentage >= 70) return 'Good';
      if (percentage >= 50) return 'Average';
      if (percentage >= 35) return 'Below Average';
      return 'Poor';
    };

    const subjectsData = Object.values(chaptersMap).map(c => {
      const percentage = c.total_marks > 0 ? (c.marks_obtained / c.total_marks) * 100 : 0;
      
      const topics = Object.values(c.topicsMap).map(t => {
        const tPerc = t.total_marks > 0 ? (t.marks_obtained / t.total_marks) * 100 : 0;
        return {
          topic: t.topic,
          total_marks: t.total_marks,
          marks_obtained: t.marks_obtained,
          score_percentage: tPerc
        };
      });
      
      return {
        subject: c.subject,
        subject_display: c.subject_display,
        total_exams: c.examSet.size,
        total_marks: c.total_marks,
        marks_obtained: c.marks_obtained,
        combined_score: percentage,
        performance_rating: getRating(percentage),
        topics: topics
      };
    });

    const overallPercentage = totalMarksAll > 0 ? (marksObtainedAll / totalMarksAll) * 100 : 0;
    const overallData = {
      total_subjects: subjectsData.length,
      total_exams: totalExams,
      total_questions: totalQuestionsAll,
      correct_answers: 0,
      accuracy_percentage: overallPercentage,
      total_marks: totalMarksAll,
      marks_obtained: marksObtainedAll,
      score_percentage: overallPercentage,
      average_score: overallPercentage,
      performance_rating: getRating(overallPercentage),
    };

    const summaryData = {
      total_online_exams: totalExams,
      total_offline_exams: 0,
      total_exams: totalExams,
      subjects_count: subjectsData.length,
      average_performance: overallPercentage,
      overall_performance: overallPercentage,
      performance_rating: getRating(overallPercentage),
    };

    res.json({
      student: studentData,
      subjects: subjectsData,
      overall: overallData,
      summary: summaryData
    });
  } catch (error) {
    console.error('Performance error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/:id', authenticateToken, async (req, res) => {
  try {
    const exam = await Exam.findById(req.params.id).populate('questions');
    if (!exam) return res.status(404).json({ message: 'Exam not found' });
    
    if (req.user.role === 'STUDENT') {
      const submission = await ExamSubmission.findOne({ exam: req.params.id, student: req.user.id });
      if (submission) {
        return res.status(403).json({ message: 'You have already submitted this exam', submissionId: submission._id });
      }
      
      const examData = exam.toObject();
      examData.questions.forEach(q => {
        delete q.correctAnswers;
      });
      return res.json(examData);
    }
    
    res.json(exam);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.post('/:id/submit', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const { answers } = req.body; 
    const exam = await Exam.findById(req.params.id).populate('questions');
    
    let totalScore = 0;
    let hasShortAnswer = false;
    
    const processedAnswers = answers.map(ans => {
      const question = exam.questions.find(q => q._id.toString() === ans.questionId);
      if (!question) return ans;
      
      let marksObtained = 0;
      let isCorrect = false;
      
      if (question.type === 'SHORT_ANSWER') {
        hasShortAnswer = true;
      } else {
        const correctSet = new Set(question.correctAnswers || []);
        const optionsArr = Array.isArray(ans.selectedOptions) ? ans.selectedOptions : [];
        const selectedSet = new Set(optionsArr);
        
        if (correctSet.size === selectedSet.size && [...correctSet].every(val => selectedSet.has(val))) {
          isCorrect = true;
          marksObtained = question.marks;
        }
        totalScore += marksObtained;
      }
      
      return { ...ans, marksObtained, isCorrect };
    });
    
    const status = hasShortAnswer ? 'PENDING_REVIEW' : 'GRADED';
    
    const submission = await ExamSubmission.create({
      exam: req.params.id,
      student: req.user.id,
      answers: processedAnswers,
      totalScore,
      status
    });
    
    res.status(201).json(submission);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/:id/submissions', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const submissions = await ExamSubmission.find({ exam: req.params.id }).populate('student', 'name email');
    res.json(submissions);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/:id/submissions/me', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const submission = await ExamSubmission.findOne({ exam: req.params.id, student: req.user.id }).populate({
      path: 'exam',
      populate: { path: 'questions' }
    });
    if (!submission) return res.status(404).json({ message: 'No submission found' });
    res.json(submission);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.put('/:id/grade/:submissionId', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const { grades } = req.body; 
    const submission = await ExamSubmission.findById(req.params.submissionId);
    if (!submission) return res.status(404).json({ message: 'Submission not found' });
    
    let totalScore = 0;
    submission.answers.forEach(ans => {
      if (grades[ans.questionId.toString()] !== undefined) {
        ans.marksObtained = grades[ans.questionId.toString()];
        ans.isCorrect = ans.marksObtained > 0;
      }
      totalScore += ans.marksObtained;
    });
    
    submission.totalScore = totalScore;
    submission.status = 'GRADED';
    submission.gradedBy = req.user.id;
    
    await submission.save();
    res.json(submission);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/stats/batch/:batchId', authenticateToken, requireRole(['TUTOR', 'MENTOR']), async (req, res) => {
  try {
    const exams = await Exam.find({ batch: req.params.batchId });
    const examIds = exams.map(e => e._id);
    const submissions = await ExamSubmission.find({ exam: { $in: examIds }, status: 'GRADED' }).populate('student', 'name');
    
    res.json({ exams, submissions });
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

router.get('/stats/student', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const submissions = await ExamSubmission.find({ student: req.user.id, status: 'GRADED' }).populate('exam', 'title');
    res.json(submissions);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
