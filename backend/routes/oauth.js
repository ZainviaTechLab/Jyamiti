import express from 'express';
import { getGoogleToken } from '../controllers/oauthController.js';

const router = express.Router();

// Fetch short-lived Google Access Token
// Note: You can add your JWT auth middleware here if you want to restrict this endpoint to logged-in tutors.
router.get('/google-token', getGoogleToken);

export default router;
