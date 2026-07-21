import cron from 'node-cron';
import Batch from '../models/Batch.js';
import Schedule from '../models/Schedule.js';
import Payment from '../models/Payment.js';
import Attendance from '../models/Attendance.js';

export const generatePaymentsForMonth = async (targetDate = new Date()) => {
  console.log(`[PaymentGenerator] Running payment generation for date: ${targetDate.toDateString()}`);
  try {
    // Determine the previous month
    const year = targetDate.getFullYear();
    const month = targetDate.getMonth(); // 0-indexed
    
    // If targetDate is May (4), previous month is April (3)
    let prevMonth = month - 1;
    let prevYear = year;
    if (prevMonth < 0) {
      prevMonth = 11;
      prevYear = year - 1;
    }
    
    const startDate = new Date(prevYear, prevMonth, 1);
    const endDate = new Date(prevYear, prevMonth + 1, 0, 23, 59, 59, 999);
    
    // Format YYYY-MM
    const monthStr = `${prevYear}-${String(prevMonth + 1).padStart(2, '0')}`;
    
    console.log(`[PaymentGenerator] Target period: ${startDate.toDateString()} to ${endDate.toDateString()} (${monthStr})`);
    
    // Get all batches with their categories
    const batches = await Batch.find().populate('category');
    if (!batches.length) {
      console.log('[PaymentGenerator] No batches found.');
      return;
    }
    
    let generatedCount = 0;
    
    for (const batch of batches) {
      if (!batch.category || !batch.category.fees) continue;
      if (!batch.students || batch.students.length === 0) continue;
      
      const feePerSession = batch.category.fees;
      
      // We will calculate sessions per student based on attendance
      // So we just get the schedule IDs for the month
      const schedules = await Schedule.find({
        batch: batch._id,
        date: { $gte: startDate, $lte: endDate }
      });
      
      if (schedules.length === 0) continue; // No sessions, no fee
      const scheduleIds = schedules.map(s => s._id);
      
      // Due date is 7th of the current month
      const dueDate = new Date(year, month, 7, 23, 59, 59);
      
      for (const studentId of batch.students) {
        try {
          const existingPayment = await Payment.findOne({
            student: studentId,
            batch: batch._id,
            monthYear: monthStr
          });
          
          if (!existingPayment) {
            // Calculate billable sessions from attendance
            const attendances = await Attendance.find({
              schedule: { $in: scheduleIds },
              student: studentId,
              status: { $in: ['Present', 'Absent'] }
            });
            
            const sessionsCount = attendances.length;
            if (sessionsCount === 0) continue;
            
            const amountDue = sessionsCount * feePerSession;

            await Payment.create({
              student: studentId,
              batch: batch._id,
              monthYear: monthStr,
              sessionsCount,
              feePerSession,
              amountDue,
              status: 'PENDING',
              dueDate
            });
            generatedCount++;
          }
        } catch (err) {
          console.error(`[PaymentGenerator] Error generating payment for student ${studentId}:`, err);
        }
      }
    }
    
    console.log(`[PaymentGenerator] Generated ${generatedCount} new payments.`);
  } catch (error) {
    console.error('[PaymentGenerator] Error generating payments:', error);
  }
};

// Run monthly at midnight on the 1st
export const initPaymentCron = () => {
  cron.schedule('0 0 1 * *', () => {
    generatePaymentsForMonth();
  });
};
