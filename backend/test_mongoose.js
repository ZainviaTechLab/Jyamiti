import mongoose from 'mongoose';
import Course from './models/Course.js';

async function run() {
  await mongoose.connect('mongodb://localhost:27017/jyamiti');
  try {
    const course = await Course.findOne({ name: 'CBSE' });
    console.log('Before save:', JSON.stringify(course.syllabus, null, 2));
    course.syllabus = [
      {
        title: 'First chapter',
        topics: [
          {
            title: 'New Diagnostic Topic',
            subTopics: [
              { title: 'Sub diagnostic' }
            ]
          }
        ]
      }
    ];
    await course.save();
    const updated = await Course.findOne({ name: 'CBSE' });
    console.log('After save:', JSON.stringify(updated.syllabus, null, 2));
  } catch (err) {
    console.error('Error:', err);
  }
  process.exit(0);
}

run();
