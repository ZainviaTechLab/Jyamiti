// Utility functions for checking scheduling conflicts

/**
 * Parses a time string like "10:00 AM - 12:00 PM" into minutes from midnight.
 * @param {string} timeStr 
 * @returns {{start: number, end: number}|null}
 */
export function parseTimePeriod(timeStr) {
  if (!timeStr) return null;
  const parts = timeStr.split('-');
  if (parts.length !== 2) return null;
  
  const parseTime = (t) => {
    const [time, modifier] = t.trim().split(' ');
    if (!time || !modifier) throw new Error("Invalid format");
    let [hours, minutes] = time.split(':').map(Number);
    if (modifier.toUpperCase() === 'PM' && hours !== 12) hours += 12;
    if (modifier.toUpperCase() === 'AM' && hours === 12) hours = 0;
    return hours * 60 + (minutes || 0);
  };
  
  try {
    return {
      start: parseTime(parts[0]),
      end: parseTime(parts[1])
    };
  } catch (e) {
    return null;
  }
}

/**
 * Checks if the proposed days and time overlap with any existing batches.
 * @param {string} newDaysStr - e.g. "Monday,Wednesday"
 * @param {string} newTimeStr - e.g. "10:00 AM - 12:00 PM"
 * @param {Array} existingBatches - Array of batch documents/objects
 * @returns {Object|null} Conflict details if overlap exists, else null
 */
export function hasScheduleConflict(newDaysStr, newTimeStr, existingBatches) {
  if (!newDaysStr || !newTimeStr || !existingBatches || existingBatches.length === 0) {
    return null;
  }

  const newDays = newDaysStr.split(',').map(d => d.trim().toLowerCase());
  const newTime = parseTimePeriod(newTimeStr);
  if (!newTime) return null;

  for (const batch of existingBatches) {
    if (!batch.daysOfWeek || !batch.timePeriod) continue;
    
    const existingDays = batch.daysOfWeek.split(',').map(d => d.trim().toLowerCase());
    
    const overlappingDays = newDays.filter(day => existingDays.includes(day));
    if (overlappingDays.length > 0) {
      const existingTime = parseTimePeriod(batch.timePeriod);
      if (existingTime) {
        if (newTime.start < existingTime.end && newTime.end > existingTime.start) {
          // Found an overlap
          return {
            batchName: batch.name,
            day: overlappingDays[0].charAt(0).toUpperCase() + overlappingDays[0].slice(1),
            time: batch.timePeriod
          };
        }
      }
    }
  }
  
  return null;
}
