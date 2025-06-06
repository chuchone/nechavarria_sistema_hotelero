import {
  getHoteles,
  getHotelById,
  getHabitacionesByHotel
} from '../models/hotelesModel.js';

export const listarHoteles = async (req, res) => {
  try {
    const hoteles = await getHoteles();
    res.json(hoteles);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

export const obtenerHotel = async (req, res) => {
  try {
    const hotel = await getHotelById(req.params.id);
    if (!hotel) {
      return res.status(404).json({ message: 'Hotel no encontrado' });
    }
    res.json(hotel);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

export const habitacionesHotel = async (req, res) => {
  try {
    const habitaciones = await getHabitacionesByHotel(req.params.id);
    res.json(habitaciones);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};