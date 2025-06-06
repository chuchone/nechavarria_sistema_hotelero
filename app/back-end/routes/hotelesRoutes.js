import { Router } from 'express';
import {
  listarHoteles,
  obtenerHotel,
  habitacionesHotel
} from '../controllers/hotelesController.js';

const router = Router();

router.get('/', listarHoteles);
router.get('/:id', obtenerHotel);
router.get('/:id/habitaciones', habitacionesHotel);

export default router;