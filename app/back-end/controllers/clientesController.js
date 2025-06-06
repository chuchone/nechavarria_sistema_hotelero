import {
  createCliente,
  getClienteById,
  updateCliente,
  getClientes
} from '../models/clientesModel.js';

export const crearCliente = async (req, res) => {
  try {
    const nuevoCliente = await createCliente(req.body);
    res.status(201).json(nuevoCliente);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

export const obtenerCliente = async (req, res) => {
  try {
    const cliente = await getClienteById(req.params.id);
    if (!cliente) {
      return res.status(404).json({ message: 'Cliente no encontrado' });
    }
    res.json(cliente);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

export const actualizarCliente = async (req, res) => {
  try {
    const clienteActualizado = await updateCliente(req.params.id, req.body);
    if (!clienteActualizado) {
      return res.status(404).json({ message: 'Cliente no encontrado' });
    }
    res.json(clienteActualizado);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

export const listarClientes = async (req, res) => {
  try {
    const clientes = await getClientes();
    res.json(clientes);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};