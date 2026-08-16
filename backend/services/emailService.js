import fs from 'fs';
import path from 'path';
import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

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

export async function sendEmail({ to, subject, text, html }) {
  if (!process.env.RESEND_API_KEY) {
    console.warn('[EMAIL] Resend not configured — falling back to local log.');
    logEmail(to, subject, text || html);
    return;
  }

  try {
    const fromAddress = process.env.RESEND_FROM || 'Jyamiti Math Learning <noreply@YOUR-VERIFIED-DOMAIN.com>';
    
    const { data, error } = await resend.emails.send({
      from: fromAddress,
      to,
      subject,
      text,
      html,
    });

    if (error) {
      console.error('[RESEND ERROR]', error);
      console.error('[EMAIL] Falling back to local log file.');
      logEmail(to, subject, text || html);
      return;
    }

    console.log(`[EMAIL SENT] to: ${to} | Subject: ${subject} | ID: ${data?.id}`);
  } catch (err) {
    console.error('[RESEND CATCH ERROR]', err.message);
    logEmail(to, subject, text || html);
  }
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
