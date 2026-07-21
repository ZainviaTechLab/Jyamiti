import express from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import User from '../models/User.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';
import { sendWelcomeEmail } from '../services/emailService.js';

const router = express.Router();

function generateTempPassword() {
  return crypto.randomBytes(4).toString('hex');
}

router.use(authenticateToken, requireRole(['ADMIN']));

// GET /api/users
router.get('/', async (req, res) => {
  try {
    const { role, page, limit } = req.query;
    const filter = role
      ? { role: role.toUpperCase() }
      : { role: { $in: ['STUDENT', 'TUTOR', 'MENTOR'] } };

    let query = User.find(filter).select('-password').sort({ createdAt: -1 });

    if (page && limit) {
      const pageNum = parseInt(page);
      const limitNum = parseInt(limit);
      const skip = (pageNum - 1) * limitNum;
      
      const users = await query.skip(skip).limit(limitNum);
      const mappedUsers = users.map(u => ({ id: u._id, email: u.email, name: u.name, phone: u.phone, role: u.role, createdAt: u.createdAt }));
      
      const totalCount = await User.countDocuments(filter);
      
      return res.json({
        data: mappedUsers,
        hasMore: skip + users.length < totalCount
      });
    }

    const users = await query;
    res.json(users.map(u => ({ id: u._id, email: u.email, name: u.name, phone: u.phone, role: u.role, createdAt: u.createdAt })));
  } catch (error) {
    console.error('Fetch users error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/users
router.post('/', async (req, res) => {
  const { email, name, role, phone } = req.body;
  if (!email || !name || !role) {
    return res.status(400).json({ message: 'Email, name, and role are required' });
  }

  const normalizedRole = role.toUpperCase();
  if (!['STUDENT', 'TUTOR', 'MENTOR'].includes(normalizedRole)) {
    return res.status(400).json({ message: 'Invalid role. Must be STUDENT, TUTOR, or MENTOR' });
  }

  try {
    const existingUser = await User.findOne({ email: email.toLowerCase() });
    if (existingUser) return res.status(400).json({ message: 'Email is already registered' });

    const tempPassword = generateTempPassword();
    const hashedPassword = await bcrypt.hash(tempPassword, 10);

    const newUser = await User.create({
      email: email.toLowerCase(),
      name,
      phone,
      role: normalizedRole,
      password: hashedPassword,
    });

    sendWelcomeEmail(newUser.email, newUser.name, tempPassword, newUser.role)
      .catch(emailError => {
        console.error('Failed to send welcome email (async):', emailError);
      });

    res.status(201).json({ id: newUser._id, email: newUser.email, name: newUser.name, phone: newUser.phone, role: newUser.role, createdAt: newUser.createdAt });
  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// PUT /api/users/:id
router.put('/:id', async (req, res) => {
  const { id } = req.params;
  const { email, name, phone } = req.body;
  try {
    const user = await User.findById(id);
    if (!user) return res.status(404).json({ message: 'User not found' });
    if (user.role === 'ADMIN') return res.status(403).json({ message: 'Cannot modify admin users' });

    if (email && email.toLowerCase() !== user.email) {
      const taken = await User.findOne({ email: email.toLowerCase() });
      if (taken) return res.status(400).json({ message: 'Email is already in use' });
    }

    user.name = name || user.name;
    user.email = email ? email.toLowerCase() : user.email;
    if (phone !== undefined) user.phone = phone;
    await user.save();

    res.json({ id: user._id, email: user.email, name: user.name, phone: user.phone, role: user.role });
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// DELETE /api/users/:id
router.delete('/:id', async (req, res) => {
  const { id } = req.params;
  try {
    const user = await User.findById(id);
    if (!user) return res.status(404).json({ message: 'User not found' });
    if (user.role === 'ADMIN') return res.status(403).json({ message: 'Cannot delete admin users' });

    await User.findByIdAndDelete(id);
    res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;