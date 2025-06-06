import express from 'express';
import passport from 'passport';
import bcrypt from 'bcryptjs';
import { pool } from '../config/db.js';

const router = express.Router();

// Registro de usuario
router.post('/register', async (req, res) => {
  const { nombre, email, password, documento_identidad } = req.body;

  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    
    const result = await pool.query(
      `INSERT INTO clientes 
       (nombre, email, documento_identidad, password_hash) 
       VALUES ($1, $2, $3, $4) RETURNING cliente_id, nombre, email`,
      [nombre, email, documento_identidad, hashedPassword]
    );

    // Iniciar sesión automáticamente después del registro
    req.login(result.rows[0], (err) => {
      if (err) throw err;
      res.redirect('/mi-cuenta');
    });

  } catch (error) {
    console.error(error);
    res.status(500).send('Error al registrar usuario');
  }
});

// Inicio de sesión
router.post('/login', passport.authenticate('local', {
  successRedirect: '/mi-cuenta',
  failureRedirect: '/login',
  failureFlash: true
}));

// Cerrar sesión
router.get('/logout', (req, res) => {
  req.logout((err) => {
    if (err) return res.status(500).send('Error al cerrar sesión');
    res.redirect('/');
  });
});

export default router;