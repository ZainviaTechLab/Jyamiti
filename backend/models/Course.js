import mongoose from 'mongoose';

const slideSchema = new mongoose.Schema({
  id: { type: String },
  title: { type: String, required: true },
  image: { type: String, default: '' },
  content: { type: String, default: '' },
  description: { type: String, default: '' },
  courseId: { type: String, default: '' },
  courseName: { type: String, default: '' },
  slides: { type: [mongoose.Schema.Types.Mixed], default: [] },
}, { _id: false, strict: false });

const videoSchema = new mongoose.Schema({
  title: { type: String, required: true },
  url: { type: String, required: true }
});

const optionSchema = new mongoose.Schema({
  text: { type: String, default: '' },
  imageUrl: { type: String, default: '' },
  isSvg: { type: Boolean, default: false }
});

const geometryNodeSchema = new mongoose.Schema({
  id: { type: String, required: true },
  label: { type: String, default: '' },
  x: { type: Number, required: true },
  y: { type: Number, required: true },
  isFixed: { type: Boolean, default: false }
});

const svgLabelSchema = new mongoose.Schema({
  id: { type: String, required: true },
  text: { type: String, required: true },
  x: { type: Number, required: true },
  y: { type: Number, required: true },
  color: { type: String, default: '#000000' },
  fontSize: { type: Number, default: 14 },
  fontWeight: { type: String, default: 'normal' },
  alignment: { type: String, default: 'center' },
  isVisible: { type: Boolean, default: true }
});

const practiceQuestionSchema = new mongoose.Schema({
  grade: { type: Number, required: true },
  type: { type: String, required: true },
  descriptiveText: { type: String, default: '' },
  text: { type: String, required: true },
  isSvg: { type: Boolean, default: false },
  questionImage: { type: String, default: '' },
  options: [optionSchema],
  rightOptions: [optionSchema],
  geometryNodes: [geometryNodeSchema],
  geometryLinesCount: { type: Number, default: 1 },
  hideGeometryNodes: { type: Boolean, default: false },
  correctAnswers: [{ type: String }],
  marks: { type: Number, default: 1 },
  shortAnswerPrefix: { type: String, default: '' },
  shortAnswerSuffix: { type: String, default: '' },
  shortAnswerHint: { type: String, default: '' },
  svgLabels: [svgLabelSchema]
});

const subTopicSchema = new mongoose.Schema({
  title: { type: String, required: true },
  videos: [videoSchema],
  slides: [slideSchema],
  practiceQuestions: [practiceQuestionSchema]
});

const topicSchema = new mongoose.Schema({
  title: { type: String, required: true },
  subTopics: [subTopicSchema],
  videos: [videoSchema],
  slides: [slideSchema],
  practiceQuestions: [practiceQuestionSchema]
});

const courseSchema = new mongoose.Schema({
  name: { type: String, required: true, unique: true },
  description: { type: String, default: '' },
  grade: { type: String, default: '' },
  subject: { type: String, default: '' },
  syllabus: [
    {
      title: { type: String, required: true }, // Chapter/Unit
      topics: [topicSchema],
      videos: [videoSchema],
      slides: [slideSchema],
      practiceQuestions: [practiceQuestionSchema]
    }
  ]
}, { timestamps: true });

export default mongoose.model('Course', courseSchema);
