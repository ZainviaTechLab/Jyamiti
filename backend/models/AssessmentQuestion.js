import mongoose from 'mongoose';

const assessmentQuestionSchema = new mongoose.Schema({
  grade: { 
    type: Number, 
    required: true, 
    min: 1, 
    max: 12 
  },
  type: { 
    type: String, 
    enum: ['MCQ_SINGLE', 'MCQ_MULTI', 'SHORT_ANSWER', 'ORDERING', 'MATCHING', 'GEOMETRIC', 'MATRIX_MCQ', 'MATRIX_INPUT', 'EQUATION', 'STATEMENT_DROPDOWN', 'INLINE_SELECT'],
    required: true 
  },
  descriptiveText: {
    type: String,
    default: ''
  },
  text: { 
    type: String, 
    required: true 
  },
  isSvg: { 
    type: Boolean, 
    default: false 
  },
  questionImage: { 
    type: String, 
    default: '' 
  },
  options: [{
    text: { type: String, default: '' },
    imageUrl: { type: String, default: '' },
    isSvg: { type: Boolean, default: false }
  }],
  rightOptions: [{
    text: { type: String, default: '' },
    imageUrl: { type: String, default: '' },
    isSvg: { type: Boolean, default: false }
  }],
  geometryNodes: [{
    id: { type: String, required: true },
    label: { type: String, default: '' },
    x: { type: Number, required: true },
    y: { type: Number, required: true },
    isFixed: { type: Boolean, default: false }
  }],
  geometryLinesCount: { 
    type: Number, 
    default: 1 
  },
  hideGeometryNodes: {
    type: Boolean,
    default: false
  },
  correctAnswers: [{ 
    type: String 
  }],
  marks: { 
    type: Number, 
    default: 1 
  },
  shortAnswerPrefix: {
    type: String,
    default: ''
  },
  shortAnswerSuffix: {
    type: String,
    default: ''
  },
  shortAnswerHint: {
    type: String,
    default: ''
  },
  svgLabels: [{
    id: { type: String, required: true },
    text: { type: String, required: true },
    x: { type: Number, required: true },
    y: { type: Number, required: true },
    color: { type: String, default: '#000000' },
    fontSize: { type: Number, default: 14 },
    fontWeight: { type: String, default: 'normal' },
    alignment: { type: String, default: 'center' },
    isVisible: { type: Boolean, default: true }
  }]
}, { timestamps: true });

export default mongoose.model('AssessmentQuestion', assessmentQuestionSchema);
