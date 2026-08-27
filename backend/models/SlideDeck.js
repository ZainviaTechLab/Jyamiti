import mongoose from 'mongoose';

const slideBlockSchema = new mongoose.Schema({
  id: { type: String, required: true },
  type: {
    type: String,
    enum: ['heading', 'subheading', 'paragraph', 'code', 'list', 'callout', 'image', 'latexMath'],
    required: true,
  },
  content: { type: String, default: '' },
  language: { type: String, default: 'dart' },
  imageUrl: { type: String, default: '' },
  caption: { type: String, default: '' },
  calloutType: { type: String, default: 'info' },
});

const slideQuizSchema = new mongoose.Schema({
  id: { type: String, required: true },
  questionText: { type: String, required: true },
  options: [{ type: String }],
  correctOptionIndex: { type: Number, required: true },
  explanation: { type: String, default: '' },
});

const slideItemSchema = new mongoose.Schema({
  id: { type: String, required: true },
  slideIndex: { type: Number, required: true },
  title: { type: String, required: true },
  theme: { type: String, default: 'darkGlass' },
  imageUrl: { type: String, default: '' },
  blocks: [slideBlockSchema],
  quizzes: [slideQuizSchema],
  quiz: {
    question: { type: String },
    options: [{ type: String }],
    correctIndex: { type: Number },
    explanation: { type: String },
  },
  enableWhiteboard: { type: Boolean, default: true },
});

const slideDeckSchema = new mongoose.Schema(
  {
    id: { type: String, required: true, unique: true },
    courseId: { type: String, required: true },
    courseName: { type: String, required: true },
    title: { type: String, required: true },
    description: { type: String, default: '' },
    isDownloadedOffline: { type: Boolean, default: false },
    slides: [slideItemSchema],
  },
  { timestamps: true }
);

const slideProgressSchema = new mongoose.Schema(
  {
    deckId: { type: String, required: true },
    userId: { type: String, default: 'stu_current' },
    timeSpentPerSlide: { type: Map, of: Number, default: {} },
    completedSlides: { type: Map, of: Boolean, default: {} },
    bookmarkedSlides: { type: Map, of: Boolean, default: {} },
    quizAnswers: { type: Map, of: Number, default: {} },
    slideDrawings: { type: Map, of: String, default: {} },
    lastViewedSlideIndex: { type: Number, default: 0 },
  },
  { timestamps: true }
);

export const SlideDeck = mongoose.model('SlideDeck', slideDeckSchema);
export const SlideProgress = mongoose.model('SlideProgress', slideProgressSchema);
