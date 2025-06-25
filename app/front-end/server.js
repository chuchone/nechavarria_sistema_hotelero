import express from 'express';
import session from 'express-session';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = 4000;

// Configuración de EJS
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Middlewares
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(session({
  secret: 'tu_secreto',
  resave: false,
  saveUninitialized: true
}));

app.use((req, res, next) => {
  // Puedes obtener el usuario de la sesión si usas autenticación
  res.locals.user = req.session.user || null; // Si no hay sesión, será null
  next();
});

// Rutas Básicas
app.get('/', (req, res) => {
  res.render('index', { title: 'Grupo Hoteles Las Shakiras' });
});

// Auth Routes
app.get('/login', (req, res) => {
  res.render('auth/login', { title: 'Iniciar Sesión' });
});

app.get('/register', (req, res) => {
  res.render('auth/register', { title: 'Crear Usuario' });
});

// Hotels Routes
app.get('/hoteles', (req, res) => {
  res.render('hotels/index', { 
    title: 'Nuestros Hoteles',
    sections: ['habitaciones', 'reservaciones', 'pagos', 'servicios', 'lugares', 'politicas', 'tarifas']
  });
});

// User Routes
app.get('/mi-cuenta', (req, res) => {
  res.render('user/account', {
    title: 'Mi Cuenta',
    sections: ['perfil', 'pagos', 'fidelizacion', 'historico']
  });
});

app.listen(PORT, () => {
  console.log(`Frontend corriendo en http://localhost:${PORT}`);
});