import dotenv from 'dotenv';
import nodemailer from 'nodemailer';

dotenv.config();

console.log('--- SMTP CONNECTION TEST ---');
console.log('SMTP_HOST  :', process.env.SMTP_HOST);
console.log('SMTP_PORT  :', process.env.SMTP_PORT);
console.log('SMTP_SECURE:', process.env.SMTP_SECURE);
console.log('SMTP_USER  :', process.env.SMTP_USER);
console.log('SMTP_PASS  :', process.env.SMTP_PASS ? `"${process.env.SMTP_PASS}" (${process.env.SMTP_PASS.length} chars)` : 'NOT SET');
console.log('SMTP_FROM  :', process.env.SMTP_FROM);
console.log('');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_SECURE === 'true',
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
  tls: { rejectUnauthorized: false },
});

console.log('Verifying SMTP connection...');
try {
  await transporter.verify();
  console.log('✅ SMTP connection SUCCESSFUL!');

  console.log('Sending test email...');
  const info = await transporter.sendMail({
    from: process.env.SMTP_FROM,
    to: process.env.SMTP_USER,
    subject: 'Platform SMTP Test',
    text: 'If you received this, SMTP is working correctly!',
  });
  console.log('✅ Test email sent! Message ID:', info.messageId);
} catch (err) {
  console.error('❌ SMTP ERROR:', err.message);
  console.error('Full error:', err);
}
