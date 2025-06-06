import { configureAuth } from './auth/config.js';
import authRoutes from './auth/routes.js';

const app = express();

// Configura autenticación
configureAuth(app);

// Usa las rutas de autenticación
app.use(authRoutes);

// Middleware para pasar user a las vistas
app.use((req, res, next) => {
  res.locals.user = req.user || null;
  next();
});