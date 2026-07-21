import fs from 'fs';
import path from 'path';
import nodemailer from 'nodemailer';

const LOG_DIR = path.resolve('logs');
const LOG_FILE = path.join(LOG_DIR, 'sent_emails.log');

// Ensure log directory exists
if (!fs.existsSync(LOG_DIR)) {
  fs.mkdirSync(LOG_DIR, { recursive: true });
}

function logEmail(to, subject, body) {
  const logEntry = `
========================================
TIMESTAMP: ${new Date().toISOString()}
TO: ${to}
SUBJECT: ${subject}
BODY:
${body}
========================================
\n`;
  fs.appendFileSync(LOG_FILE, logEntry, 'utf8');
  console.log(`[EMAIL LOGGED] Sent to: ${to} | Subject: ${subject}`);
}

// Lazy-create transporter on first use so env vars are always loaded
function getTransporter() {
  const host = process.env.SMTP_HOST;
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!host || !user || !pass) {
    console.warn('[EMAIL] SMTP not configured — falling back to local log.');
    return null;
  }

  return nodemailer.createTransport({
    host,
    port: parseInt(process.env.SMTP_PORT || '587'),
    secure: process.env.SMTP_SECURE === 'true',
    auth: { user, pass },
    tls: { rejectUnauthorized: false }, // allow self-signed certs in dev
  });
}

export async function sendEmail({ to, subject, text, html }) {
  const transporter = getTransporter();

  if (transporter) {
    try {
      // Verify connection first
      await transporter.verify();
      await transporter.sendMail({
        from: process.env.SMTP_FROM || '"Jyamiti Math Learning" <no-reply@jyamitimath.com>',
        to,
        subject,
        text,
        html,
      });
      console.log(`[EMAIL SENT] to: ${to} | Subject: ${subject}`);
      return;
    } catch (err) {
      console.error('[SMTP ERROR]', err.message);
      console.error('[SMTP] Falling back to local log file.');
    }
  }

  // Fallback: log email to file
  logEmail(to, subject, text || html);
}

export async function sendWelcomeEmail(email, name, password, role) {
  const subject = 'Welcome to the Jyamiti Math Learning - Your Credentials';
  const text = `Hi ${name},\n\nYou have been registered as a ${role.toLowerCase()} on our platform.\n\nYour login credentials:\nEmail: ${email}\nPassword: ${password}\n\nPlease login at your earliest convenience.\n\nBest regards,\nPlatform Admin`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 500px; margin: auto; padding: 24px; background: #f9f9f9; border-radius: 8px;">
      <h2 style="color: #4F46E5;">Welcome to the Jyamiti Math Learning!</h2>
      <p>Hi <strong>${name}</strong>,</p>
      <p>You have been registered as a <strong>${role.toLowerCase()}</strong> on our platform.</p>
      <p>Your login credentials:</p>
      <table style="background: #fff; border-radius: 8px; padding: 16px; width: 100%;">
        <tr><td><strong>Email:</strong></td><td>${email}</td></tr>
        <tr><td><strong>Password:</strong></td><td style="font-family: monospace; font-size: 16px;">${password}</td></tr>
      </table>
      <p style="margin-top: 20px;">Please login and change your password.</p>
      <p>Best regards,<br/><strong>Jyamiti Math Academy</strong></p>
    </div>
  `;
  await sendEmail({ to: email, subject, text, html });
}

export async function sendPasswordResetEmail(email, token) {
  const subject = 'Password Reset Code';
  const text = `You requested a password reset.\n\nYour 6-digit reset code: ${token}\n\nThis code expires in 1 hour.`;
  const html = `
    <div style="font-family: Arial, sans-serif; max-width: 500px; margin: auto; padding: 24px; background: #f9f9f9; border-radius: 8px;">
      <h2 style="color: #4F46E5;">Password Reset Request</h2>
      <p>Use the code below to reset your password:</p>
      <div style="text-align: center; margin: 24px 0;">
        <span style="background: #4F46E5; color: white; font-size: 28px; font-weight: bold; letter-spacing: 6px; padding: 12px 24px; border-radius: 8px;">${token}</span>
      </div>
      <p>This code expires in <strong>1 hour</strong>.</p>
      <p>If you did not request this, please ignore this email.</p>
    </div>
  `;
  await sendEmail({ to: email, subject, text, html });
}
