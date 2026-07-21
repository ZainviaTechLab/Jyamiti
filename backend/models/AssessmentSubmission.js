import mongoose from 'mongoose';

const assessmentSubmissionSchema = new mongoose.Schema({
  name: { 
    type: String, 
    required: true 
  },
  whatsappNumber: { 
    type: String, 
    required: true, 
    unique: true 
  },
  grade: { 
    type: Number, 
    required: true 
  },
  score: { 
    type: Number, 
    required: true 
  },
  totalQuestions: { 
    type: Number, 
    required: true 
  },
  answers: [{
    questionId: { 
      type: mongoose.Schema.Types.ObjectId, 
      ref: 'AssessmentQuestion',
      required: true
    },
    selectedAnswers: [{ 
      type: String 
    }],
    isCorrect: { 
      type: Boolean,
      required: true
    }
  }]
}, { timestamps: true });

export default mongoose.model('AssessmentSubmission', assessmentSubmissionSchema);
