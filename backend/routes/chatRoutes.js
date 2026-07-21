import express from 'express';
import { fetchChats, fetchMessages } from '../controllers/chatController.js';
import { authenticateToken } from '../middleware/authMiddleware.js';

const router = express.Router();

router.route('/').get(authenticateToken, fetchChats);
router.route('/:chatId/messages').get(authenticateToken, fetchMessages);

export default router;
