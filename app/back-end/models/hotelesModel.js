import { pool } from '../config/db.js';

export const getHoteles = async () => {
  const result = await pool.query('SELECT * FROM hoteles WHERE activo = true');
  return result.rows;
};

export const getHotelById = async (hotelId) => {
  const result = await pool.query('SELECT * FROM hoteles WHERE hotel_id = $1', [hotelId]);
  return result.rows[0];
};

export const getHabitacionesByHotel = async (hotelId) => {
  const query = `
    SELECT h.*, th.nombre as tipo_habitacion 
    FROM habitaciones h
    LEFT JOIN tipos_habitacion th ON h.tipo_id = th.tipo_id
    WHERE h.hotel_id = $1
  `;
  const result = await pool.query(query, [hotelId]);
  return result.rows;
};