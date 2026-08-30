import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkeychangeinproduction';

export function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ message: 'Authentication token is required' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ message: 'Invalid or expired token' });
    }
    req.user = user;
    next();
  });
}

export function requireRole(roles) {
  // Case-insensitive on purpose: req.user.role is always uppercase (it's
  // issued straight from User.role, whose enum is ADMIN/TUTOR/MENTOR/
  // STUDENT), but several call sites have passed lowercase role names --
  // a case-sensitive check silently locked out every legitimate user who
  // hit one of those routes. Normalizing here fixes it at the root instead
  // of relying on every route remembering to spell roles in uppercase.
  const normalizedRoles = roles.map((r) => String(r).toUpperCase());
  return (req, res, next) => {
    const userRole = req.user ? String(req.user.role || '').toUpperCase() : '';
    if (!userRole || !normalizedRoles.includes(userRole)) {
      return res.status(403).json({ message: 'Access denied: insufficient permissions' });
    }
    next();
  };
}
