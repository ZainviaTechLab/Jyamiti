import mongoose from 'mongoose';

const slideBlockSchema = new mongoose.Schema(
  {
    id: { type: String, required: true },
    type: {
      type: String,
      enum: [
        // 16 core Flutter slide block types
        'heading',
        'subheading',
        'paragraph',
        'code',
        'bulletList',
        'callout',
        'imageUrl',
        'math',
        'svg',
        'table',
        'video',
        'card',
        'columns',
        'banner',
        'text',
        'container',
        // Legacy aliases for backward compatibility
        'list',
        'image',
        'latexMath',
      ],
      required: true,
    },
    content: { type: String, default: '' },
    extra: { type: String, default: null },
    caption: { type: String, default: null },

    // Styling & Typography
    backgroundColor: { type: String, default: null },
    textColor: { type: String, default: null },
    borderColor: { type: String, default: null },
    borderWidth: { type: Number, default: 0 },
    borderRadius: { type: Number, default: null },
    fontSize: { type: Number, default: null },
    fontFamily: { type: String, default: null },
    bold: { type: Boolean, default: false },
    italic: { type: Boolean, default: false },
    underline: { type: Boolean, default: false },
    strikethrough: { type: Boolean, default: false },

    // Layout & Sizing
    padding: { type: Number, default: null },
    marginVertical: { type: Number, default: null },
    width: { type: Number, default: null },
    minHeight: { type: Number, default: null },
    horizontalAlign: { type: String, default: null },
    verticalAlign: { type: String, default: null },
    selfAlign: { type: String, default: null },
    selfAlignVertical: { type: String, default: null },
    columnMainAxisAlignment: { type: String, default: null },
    fitContent: { type: Boolean, default: false },

    // Glassmorphic effect
    glass: { type: Boolean, default: false },
    glassStyle: { type: String, default: null },
  },
  { _id: false, strict: false }
);

const slideQuizSchema = new mongoose.Schema(
  {
    question: { type: String, default: '' },
    options: [{ type: String }],
    correctIndex: { type: Number, default: 0 },
    explanation: { type: String, default: '' },
    // Backward compatibility aliases
    questionText: { type: String },
    correctOptionIndex: { type: Number },
  },
  { _id: false, strict: false }
);

const slideItemSchema = new mongoose.Schema(
  {
    id: { type: String, required: true },
    slideIndex: { type: Number, required: true },
    title: { type: String, default: '' },
    theme: { type: String, default: 'darkGlass' },
    blocks: [slideBlockSchema],
    quiz: { type: slideQuizSchema, default: null },
    enableWhiteboard: { type: Boolean, default: true },
    backgroundType: {
      type: String,
      enum: ['theme', 'solidColor', 'gradient', 'image'],
      default: 'theme',
    },
    backgroundColor: { type: String, default: null },
    backgroundColor2: { type: String, default: null },
    backgroundImageUrl: { type: String, default: null },
  },
  { _id: false, strict: false }
);

const slideDeckSchema = new mongoose.Schema(
  {
    id: { type: String, required: true, unique: true },
    courseId: { type: String, required: true },
    courseName: { type: String, required: true },
    title: { type: String, required: true },
    description: { type: String, default: '' },
    slides: [slideItemSchema],
    isPublished: { type: Boolean, default: true },
    isDownloadedOffline: { type: Boolean, default: false },
    createdAt: { type: Date, default: Date.now },
  },
  { timestamps: true, strict: false }
);

const slideProgressSchema = new mongoose.Schema(
  {
    deckId: { type: String, required: true },
    userId: { type: String, default: 'stu_current' },
    timeSpentPerSlide: { type: Map, of: Number, default: {} },
    completedSlides: [{ type: Number }],
    bookmarkedSlides: [{ type: Number }],
    quizAnswers: { type: Map, of: Number, default: {} },
    slideDrawings: { type: Map, of: String, default: {} },
    lastViewedSlideIndex: { type: Number, default: 0 },
    lastUpdated: { type: Date, default: Date.now },
  },
  { timestamps: true, strict: false }
);

export const SlideDeck = mongoose.model('SlideDeck', slideDeckSchema);
export const SlideProgress = mongoose.model('SlideProgress', slideProgressSchema);
