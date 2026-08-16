import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import User from '../models/User.js';
import Batch from '../models/Batch.js';
import PasswordResetToken from '../models/PasswordResetToken.js';
import { authenticateToken } from '../middleware/authMiddleware.js';
import { sendPasswordResetEmail } from '../services/emailService.js';

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkeychangeinproduction';

function generateNumericToken() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ message: 'Email and password are required' });
  }
  try {
    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) return res.status(401).json({ message: 'Invalid email or password' });

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) return res.status(401).json({ message: 'Invalid email or password' });

    const token = jwt.sign(
      { id: user._id, email: user.email, role: user.role, name: user.name },
      JWT_SECRET,
      { expiresIn: '7d' }
    );

    res.json({
      token,
      user: { id: user._id, email: user.email, name: user.name, role: user.role, isActive: user.isActive !== false, status: user.status || 'ACTIVE' }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// GET /api/auth/profile
router.get('/profile', authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.user.id).select('-password');
    if (!user) return res.status(404).json({ message: 'User not found' });

    let profileData = {
      id: user._id,
      email: user.email,
      name: user.name,
      role: user.role,
      isActive: user.isActive !== false,
      status: user.status || 'ACTIVE',
      createdAt: user.createdAt,
      isProfileComplete: user.isProfileComplete || false,
      phone: user.phone || '',
      bio: user.bio || '',
      qualifications: user.qualifications || '',
      experienceYears: user.experienceYears || 0,
    };

    if (user.role === 'STUDENT') {
      const batches = await Batch.find({ students: user._id })
        .populate('course', 'name description')
        .populate('tutor', 'id name email')
        .populate('mentors', 'id name email');
      profileData.batches = batches;
    } else if (user.role === 'TUTOR') {
      const batches = await Batch.find({ tutor: user._id })
        .populate('course', 'name description')
        .populate('mentors', 'id name email')
        .populate('students', 'id name email');
      profileData.batches = batches;
    } else if (user.role === 'MENTOR') {
      const batches = await Batch.find({ mentors: user._id })
        .populate('course', 'name description')
        .populate('tutor', 'id name email')
        .populate('students', 'id name email');
      profileData.batches = batches;
    }

    res.json(profileData);
  } catch (error) {
    console.error('Profile fetch error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/auth/profile
router.put('/profile', authenticateToken, async (req, res) => {
  try {
    const { phone, bio, qualifications, experienceYears, newPassword } = req.body;
    
    let updates = {
      isProfileComplete: true,
    };

    if (phone !== undefined) updates.phone = phone;
    if (bio !== undefined) updates.bio = bio;
    if (qualifications !== undefined) updates.qualifications = qualifications;
    if (experienceYears !== undefined) updates.experienceYears = experienceYears;

    if (newPassword && newPassword.trim().length >= 6) {
      const hashedPassword = await bcrypt.hash(newPassword, 10);
      updates.password = hashedPassword;
    }

    const updatedUser = await User.findByIdAndUpdate(
      req.user.id,
      { $set: updates },
      { new: true, runValidators: true }
    ).select('-password');

    if (!updatedUser) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ message: 'Profile updated successfully', user: updatedUser });
  } catch (error) {
    console.error('Profile update error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/auth/forgot-password
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ message: 'Email is required' });
  try {
    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) return res.json({ message: 'If the email exists, a reset token has been sent.' });

    const token = generateNumericToken();
    const expiresAt = new Date(Date.now() + 3600000);

    await PasswordResetToken.findOneAndDelete({ email: user.email });
    await PasswordResetToken.create({ token, email: user.email, expiresAt });

    await sendPasswordResetEmail(user.email, token);
    res.json({ message: 'If the email exists, a reset token has been sent.' });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/auth/reset-password
router.post('/reset-password', async (req, res) => {
  const { email, token, newPassword } = req.body;
  if (!email || !token || !newPassword) {
    return res.status(400).json({ message: 'Email, token, and new password are required' });
  }
  try {
    const resetRecord = await PasswordResetToken.findOne({ token, email: email.toLowerCase() });
    if (!resetRecord || resetRecord.expiresAt < new Date()) {
      return res.status(400).json({ message: 'Invalid or expired password reset token' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await User.findOneAndUpdate({ email: email.toLowerCase() }, { password: hashedPassword });
    await PasswordResetToken.findByIdAndDelete(resetRecord._id);

    res.json({ message: 'Password has been reset successfully.' });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
