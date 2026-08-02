import express from 'express';
import cors from 'cors';
import bcrypt from 'bcryptjs';
import dotenv from 'dotenv';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { connectDB } from './db.js';
import User from './models/User.js';
import authRouter from './routes/auth.js';
import usersRouter from './routes/users.js';
import coursesRouter from './routes/courses.js';
import batchesRouter from './routes/batches.js';
import worksheetsRouter from './routes/worksheets.js';
import questionsRouter from './routes/questions.js';
import examsRouter from './routes/exams.js';
import notesRouter from './routes/notes.js';
import schedulesRouter from './routes/schedules.js';
import statsRouter from './routes/stats.js';
import tutorialsRouter from './routes/tutorials.js';
import batchCategoriesRouter from './routes/batchCategories.js';
import paymentsRouter from './routes/payments.js';
import chatRouter from './routes/chatRoutes.js';
import assessmentQuestionsRouter from './routes/assessmentQuestions.js';
import assessmentSubmissionsRouter from './routes/assessmentSubmissions.js';
import assignmentsRouter from './routes/assignments.js';
import slideRouter from './routes/slideRoutes.js';
import competitionsRouter from './routes/competitions.js';
import parentMeetingsRouter from './routes/parentMeetings.js';
import { initScheduleCron } from './services/scheduleGenerator.js';
import { initPaymentCron } from './services/paymentGenerator.js';
import { initSocket } from './socket.js';
import http from 'http';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import multer from 'multer';
import Update from './models/Update.js';
import { authenticateToken, requireRole } from './middleware/authMiddleware.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config();

const app = express();

// Trust Nginx reverse proxy headers for rate limiting accuracy
app.set('trust proxy', 1);

// Secure Express apps by setting various HTTP headers
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" } // Required to allow loading uploaded media files in mobile/web clients
}));

// Enable CORS
app.use(cors());

app.use(express.json());

// API Rate Limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 300, // Limit each IP to 300 requests per 15 minutes
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many requests from this IP, please try again after 15 minutes' }
});
app.use('/api', limiter);

// Request logging
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// Mount routes
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api/courses', coursesRouter);
app.use('/api/batches', batchesRouter);
app.use('/api/worksheets', worksheetsRouter);
app.use('/api/questions', questionsRouter);
app.use('/api/exams', examsRouter);
app.use('/api/notes', notesRouter);
app.use('/api/schedules', schedulesRouter);
app.use('/api/stats', statsRouter);
app.use('/api/tutorials', tutorialsRouter);
app.use('/api/batch-categories', batchCategoriesRouter);
app.use('/api/payments', paymentsRouter);
app.use('/api/chats', chatRouter);
app.use('/api/assessment-questions', assessmentQuestionsRouter);
app.use('/api/assessment-submissions', assessmentSubmissionsRouter);
app.use('/api/assignments', assignmentsRouter);
app.use('/api/slide-decks', slideRouter);
app.use('/api/competitions', competitionsRouter);
app.use('/api/parent-meetings', parentMeetingsRouter);

// Serve uploads statically
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Setup multer storage for updates
const updatesStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    cb(null, file.originalname);
  }
});
const uploadUpdate = multer({ storage: updatesStorage });

// App updates check route for Windows
app.get('/api/updates/windows', async (req, res) => {
  try {
    const latestUpdate = await Update.findOne({ platform: 'windows' });
    if (latestUpdate) {
      return res.json({
        latestVersion: latestUpdate.latestVersion,
        latestBuildCode: latestUpdate.latestBuildCode,
        downloadUrl: latestUpdate.downloadUrl,
        releaseNotes: latestUpdate.releaseNotes
      });
    }
    res.json({
      latestVersion: '1.0.5',
      latestBuildCode: 6,
      downloadUrl: 'https://api.jyamitimath.com/uploads/jyamiti.msix',
      releaseNotes: 'Includes smooth dragging, font sizing scaling, zoom diagrams, LaTeX feedback, fullscreen animations, and try mode.'
    });
  } catch (err) {
    console.error('Error fetching updates:', err);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// App updates upload/publish route for Admin
app.post('/api/updates', authenticateToken, requireRole(['ADMIN']), uploadUpdate.single('file'), async (req, res) => {
  try {
    const { platform, latestVersion, latestBuildCode, releaseNotes } = req.body;
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    const host = req.get('host');
    const protocol = req.protocol;
    const downloadUrl = `${protocol}://${host}/uploads/${req.file.originalname}`;

    const updateRecord = await Update.findOneAndUpdate(
      { platform: platform || 'windows' },
      {
        latestVersion,
        latestBuildCode: parseInt(latestBuildCode, 10),
        releaseNotes: releaseNotes || '',
        downloadUrl,
        createdAt: new Date()
      },
      { new: true, upsert: true }
    );

    res.status(201).json({
      message: 'Update published successfully',
      update: updateRecord
    });
  } catch (err) {
    console.error('Error publishing update:', err);
    res.status(500).json({ message: 'Internal server error' });
  }
});


// Global error handler
app.use((err, req, res, next) => {
  console.error('[SERVER ERROR]', err);
  res.status(500).json({ message: 'An internal server error occurred' });
});

// Seed default Admin user
// Seed default Admin and Test users
async function seedDefaultUsers() {
  try {
    const adminCount = await User.countDocuments({ role: 'ADMIN' });
    if (adminCount === 0) {
      const hashedPassword = await bcrypt.hash('adm123', 10);
      const admin = await User.create({
        name: 'Administrator',
        email: 'admin@jyamitimath.com',
        password: hashedPassword,
        role: 'ADMIN',
      });
      console.log(`Default Admin seeded: ${admin.email}`);
    } else {
      console.log('Admin user(s) already exist.');
    }

    const testPasswordHash = await bcrypt.hash('user123', 10);

    // Tutor Seeding
    const tutorExists = await User.findOne({ email: 'test-tutor@gmail.com' });
    if (!tutorExists) {
      await User.create({
        name: 'Test Tutor',
        email: 'test-tutor@gmail.com',
        password: testPasswordHash,
        role: 'TUTOR',
      });
      console.log('Test Tutor seeded: test-tutor@gmail.com');
    }

    // Student Seeding
    const studentExists = await User.findOne({ email: 'test-student@gmail.com' });
    if (!studentExists) {
      await User.create({
        name: 'Test Student',
        email: 'test-student@gmail.com',
        password: testPasswordHash,
        role: 'STUDENT',
      });
      console.log('Test Student seeded: test-student@gmail.com');
    }

    // Mentor Seeding
    const mentorExists = await User.findOne({ email: 'test-mentor@gmail.com' });
    if (!mentorExists) {
      await User.create({
        name: 'Test Mentor',
        email: 'test-mentor@gmail.com',
        password: testPasswordHash,
        role: 'MENTOR',
      });
      console.log('Test Mentor seeded: test-mentor@gmail.com');
    }
  } catch (err) {
    console.error('Failed to seed default users:', err.message);
  }
}

const PORT = process.env.PORT || 5000;

// Connect to MongoDB first, then start server
connectDB().then(async () => {
  await seedDefaultUsers();
  initScheduleCron();
  initPaymentCron();
  const server = http.createServer(app);
  await initSocket(server);
  server.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`);
  });
});
