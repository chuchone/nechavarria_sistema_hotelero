import passport from 'passport';
import { Strategy as LocalStrategy } from 'passport-local';
import { pool } from '../config/db.js';
import bcrypt from 'bcryptjs';
import session from 'express-session';
import pgSession from 'connect-pg-simple';

const PgStore = pgSession(session);

export const configureAuth = (app) => {
  // Configuración de sesión en PostgreSQL
  app.use(session({
    store: new PgStore({
      pool: pool,
      tableName: 'user_sessions'
    }),
    secret: process.env.SESSION_SECRET || 'tu_secreto_super_seguro',
    resave: false,
    saveUninitialized: false,
    cookie: { 
      maxAge: 30 * 24 * 60 * 60 * 1000, // 30 días
      secure: process.env.NODE_ENV === 'production'
    }
  }));

  // Inicializa Passport
  app.use(passport.initialize());
  app.use(passport.session());

  // Estrategia Local (email + password)
  passport.use(new LocalStrategy({
    usernameField: 'email',
    passwordField: 'password'
  }, async (email, password, done) => {
    try {
      const result = await pool.query('SELECT * FROM clientes WHERE email = $1', [email]);
      if (result.rows.length === 0) {
        return done(null, false, { message: 'Email no registrado' });
      }

      const user = result.rows[0];
      const isValid = await bcrypt.compare(password, user.password_hash);
      
      if (!isValid) {
        return done(null, false, { message: 'Contraseña incorrecta' });
      }

      return done(null, user);
    } catch (error) {
      return done(error);
    }
  }));

  // Serialización del usuario
  passport.serializeUser((user, done) => {
    done(null, user.cliente_id);
  });

  passport.deserializeUser(async (id, done) => {
    try {
      const result = await pool.query('SELECT cliente_id, nombre, email FROM clientes WHERE cliente_id = $1', [id]);
      done(null, result.rows[0]);
    } catch (error) {
      done(error);
    }
  });
};