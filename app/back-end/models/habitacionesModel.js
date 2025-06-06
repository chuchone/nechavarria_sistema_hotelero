import { pool } from '../config/db.js';

export const getHabitacionesDisponibles = async (hotelId, fechaInicio, fechaFin) => {
  const query = `
    SELECT h.* 
    FROM habitaciones h
    WHERE h.hotel_id = $1 
    AND h.estado = 'disponible'
    AND h.habitacion_id NOT IN (
      SELECT rh.habitacion_id 
      FROM reservacion_habitaciones rh
      JOIN reservaciones r ON rh.reservacion_id = r.reservacion_id
      WHERE r.hotel_id = $1
      AND (
        (r.fecha_inicio <= $2 AND r.fecha_fin >= $2) OR
        (r.fecha_inicio <= $3 AND r.fecha_fin >= $3) OR
        (r.fecha_inicio >= $2 AND r.fecha_fin <= $3)
      )
    )
  `;
  const result = await pool.query(query, [hotelId, fechaInicio, fechaFin]);
  return result.rows;
};

export const updateEstadoHabitacion = async (habitacionId, estado) => {
  const result = await pool.query(
    'UPDATE habitaciones SET estado = $1 WHERE habitacion_id = $2 RETURNING *',
    [estado, habitacionId]
  );
  return result.rows[0];
};