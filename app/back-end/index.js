import express from 'express';
import clientesRoutes from './routes/clientesRoutes.js';
import hotelesRoutes from './routes/hotelesRoutes.js';
import { pool } from './config/db.js';

const app = express();
const PORT = 3000;

// Middleware
app.use(express.json());

// Rutas
app.use('/clientes', clientesRoutes);
app.use('/hoteles', hotelesRoutes);

// Health check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'healthy', db: 'connected' });
  } catch (error) {
    res.status(500).json({ status: 'unhealthy', db: 'disconnected' });
  }
});

app.listen(PORT, () => {
  console.log(`Servidor hotelero corriendo en http://localhost:${PORT}`);
});