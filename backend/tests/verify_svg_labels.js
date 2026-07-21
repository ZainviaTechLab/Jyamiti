import mongoose from 'mongoose';
import AssessmentQuestion from '../models/AssessmentQuestion.js';
import dotenv from 'dotenv';

dotenv.config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/jyamiti';

async function test() {
  console.log('Connecting to database:', MONGODB_URI);
  await mongoose.connect(MONGODB_URI);
  console.log('Connected successfully.');

  console.log('\nTesting: Creating a question WITH svgLabels...');
  const questionWithLabels = await AssessmentQuestion.create({
    grade: 5,
    type: 'MCQ_SINGLE',
    text: 'What is the value of x?',
    isSvg: true,
    questionImage: 'uploads/test.svg',
    svgLabels: [
      {
        id: '1',
        text: 'A',
        x: 10,
        y: 20,
        color: '#FFFFFF',
        fontSize: 16,
        fontWeight: 'bold',
        alignment: 'center',
        isVisible: true
      },
      {
        id: '2',
        text: 'B',
        x: 50,
        y: 80,
        color: '#EF4444',
        fontSize: 12,
        fontWeight: 'normal',
        alignment: 'left',
        isVisible: true
      }
    ],
    options: [
      { text: 'Option A' },
      { text: 'Option B' }
    ],
    correctAnswers: ['0'],
    marks: 1
  });
  console.log('Question with labels created! ID:', questionWithLabels._id);
  console.log('Labels saved:', questionWithLabels.svgLabels);

  console.log('\nTesting: Creating a question WITHOUT svgLabels (backward compatibility)...');
  const questionWithoutLabels = await AssessmentQuestion.create({
    grade: 6,
    type: 'SHORT_ANSWER',
    text: 'What is the sum of angles?',
    options: [],
    correctAnswers: ['180'],
    marks: 2
  });
  console.log('Question without labels created! ID:', questionWithoutLabels._id);
  console.log('Labels default:', questionWithoutLabels.svgLabels);

  console.log('\nTesting: Fetching question back from DB...');
  const fetchedQuestion = await AssessmentQuestion.findById(questionWithLabels._id);
  console.log('Fetched successfully. Labels length:', fetchedQuestion.svgLabels.length);
  if (fetchedQuestion.svgLabels.length !== 2) {
    throw new Error('Labels length mismatch!');
  }
  console.log('Fetched Label 1:', fetchedQuestion.svgLabels[0]);
  console.log('Fetched Label 2:', fetchedQuestion.svgLabels[1]);

  console.log('\nCleaning up verification data...');
  await AssessmentQuestion.findByIdAndDelete(questionWithLabels._id);
  await AssessmentQuestion.findByIdAndDelete(questionWithoutLabels._id);
  console.log('Cleaned up successfully.');

  await mongoose.disconnect();
  console.log('\nAll backend database validation tests passed successfully!');
}

test().catch(err => {
  console.error('Test failed:', err);
  process.exit(1);
});
