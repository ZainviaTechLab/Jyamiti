import cron from 'node-cron';
import Batch from '../models/Batch.js';
import Schedule from '../models/Schedule.js';
import Attendance from '../models/Attendance.js';

const dayToNum = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
};

function getDatesForWeek(startOfWeekDate) {
  const dates = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(startOfWeekDate);
    d.setDate(d.getDate() + i);
    dates.push(d);
  }
  return dates;
}

export const generateSchedules = async (specificBatchId = null) => {
  console.log(`[ScheduleGenerator] Running schedule generation${specificBatchId ? ` for batch ${specificBatchId}` : ''}...`);
  try {
    const query = specificBatchId ? { _id: specificBatchId } : {};
    const batches = await Batch.find(query).populate('students');
    if (!batches.length) return;

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    for (const batch of batches) {
      if (!batch.daysOfWeek || !batch.timePeriod) continue;
      
      const batchStartDate = batch.startDate ? new Date(new Date(batch.startDate).setHours(0,0,0,0)) : today;
      
      const startWeek = new Date(batchStartDate);
      startWeek.setDate(startWeek.getDate() - startWeek.getDay());
      
      const referenceDateForEnd = new Date(Math.max(today.getTime(), batchStartDate.getTime()));
      const endWeek = new Date(referenceDateForEnd);
      endWeek.setDate(endWeek.getDate() - endWeek.getDay() + 21); // up to week 4

      const targetWeeks = [];
      let currentW = new Date(startWeek);
      while (currentW <= endWeek) {
        targetWeeks.push(new Date(currentW));
        currentW.setDate(currentW.getDate() + 7);
      }
      if (!batch.daysOfWeek || !batch.timePeriod) continue;
      
      const batchDaysNum = batch.daysOfWeek
        .split(',')
        .map(d => d.trim().toLowerCase())
        .map(d => dayToNum[d])
        .filter(n => n !== undefined);

      const [startTime, endTime] = batch.timePeriod.split('-').map(t => t.trim());

      for (const weekStart of targetWeeks) {
        const weekDates = getDatesForWeek(weekStart);

        for (const targetDate of weekDates) {
          if (batchDaysNum.includes(targetDate.getDay())) {
            // Check if before batch startDate
            if (batch.startDate && targetDate < new Date(new Date(batch.startDate).setHours(0,0,0,0))) {
              continue;
            }
            // Check if schedule already exists
            const existingSchedule = await Schedule.findOne({
              batch: batch._id,
              date: targetDate,
            });

            if (!existingSchedule) {
              const newSchedule = await Schedule.create({
                batch: batch._id,
                date: targetDate,
                startTime: startTime || '',
                endTime: endTime || ''
              });

              // Create pending attendance for all students
              if (batch.students && batch.students.length > 0) {
                const attendanceRecords = batch.students.map(studentId => ({
                  schedule: newSchedule._id,
                  student: studentId._id || studentId,
                  status: 'Pending'
                }));
                await Attendance.insertMany(attendanceRecords);
              }
              console.log(`[ScheduleGenerator] Created schedule for batch ${batch.name} on ${targetDate.toDateString()}`);
            } else {
              // Schedule exists, ensure all current students have attendance records
              // Only do this if the schedule is in the future or today
              if (targetDate >= today && batch.students && batch.students.length > 0) {
                const existingAttendances = await Attendance.find({ schedule: existingSchedule._id });
                const existingStudentIds = existingAttendances.map(a => a.student.toString());
                
                const newStudentIds = batch.students
                  .map(s => (s._id || s).toString())
                  .filter(id => !existingStudentIds.includes(id));
                
                if (newStudentIds.length > 0) {
                  const attendanceRecords = newStudentIds.map(studentId => ({
                    schedule: existingSchedule._id,
                    student: studentId,
                    status: 'Pending'
                  }));
                  await Attendance.insertMany(attendanceRecords);
                  console.log(`[ScheduleGenerator] Added ${newStudentIds.length} missing attendance records for batch ${batch.name} on ${targetDate.toDateString()}`);
                }
              }
            }
          }
        }
      }
    }
    console.log('[ScheduleGenerator] Schedule generation completed.');
  } catch (error) {
    console.error('[ScheduleGenerator] Error generating schedules:', error);
  }
};

// Run daily at midnight
export const initScheduleCron = () => {
  cron.schedule('0 0 * * *', () => {
    generateSchedules();
  });
};
