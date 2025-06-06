import { Router } from 'express';
import {
  crearCliente,
  obtenerCliente,
  actualizarCliente,
  listarClientes
} from '../controllers/clientesController.js';

const router = Router();

router.get('/', listarClientes);
router.post('/', crearCliente);
router.get('/:id', obtenerCliente);
router.put('/:id', actualizarCliente);

export default router;