export const isAuthenticated = (req, res, next) => {
  if (req.isAuthenticated()) {
    return next();
  }
  res.redirect('/login');
};

export const isAdmin = (req, res, next) => {
  if (req.isAuthenticated() && req.user.es_admin) {
    return next();
  }
  res.status(403).send('Acceso no autorizado');
};