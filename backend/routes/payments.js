import express from 'express';
import Payment from '../models/Payment.js';
import { authenticateToken, requireRole } from '../middleware/authMiddleware.js';

const router = express.Router();

// GET /api/payments/me
router.get('/me', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const payments = await Payment.find({ student: req.user.id })
      .populate('batch', 'name')
      .sort({ createdAt: -1 });
    res.json(payments);
  } catch (error) {
    console.error('Fetch payments error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

// POST /api/payments/:id/pay (Mock payment endpoint)
router.post('/:id/pay', authenticateToken, requireRole(['STUDENT']), async (req, res) => {
  try {
    const payment = await Payment.findOne({ _id: req.params.id, student: req.user.id });
    if (!payment) {
      return res.status(404).json({ message: 'Payment not found' });
    }
    
    if (payment.status === 'PAID') {
      return res.status(400).json({ message: 'Payment is already paid' });
    }
    
    payment.status = 'PAID';
    payment.paidAt = new Date();
    await payment.save();
    
    res.json(payment);
  } catch (error) {
    console.error('Mock pay error:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
});

export default router;
