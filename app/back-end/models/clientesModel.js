import { pool } from '../config/db.js';

export const createCliente = async (clienteData) => {
  const query = `
    INSERT INTO clientes (
      nombre, documento_identidad, tipo_documento, nacionalidad, 
      telefono, email, preferencias, alergias
    ) 
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8) 
    RETURNING *
  `;
  const values = [
    clienteData.nombre,
    clienteData.documento_identidad,
    clienteData.tipo_documento,
    clienteData.nacionalidad,
    clienteData.telefono,
    clienteData.email,
    clienteData.preferencias || null,
    clienteData.alergias || null
  ];
  const result = await pool.query(query, values);
  return result.rows[0];
};

export const getClienteById = async (clienteId) => {
  const result = await pool.query('SELECT * FROM clientes WHERE cliente_id = $1', [clienteId]);
  return result.rows[0];
};

export const updateCliente = async (clienteId, updateData) => {
  const { columns, values } = buildUpdateQuery(updateData);
  const query = `UPDATE clientes SET ${columns} WHERE cliente_id = $${values.length + 1} RETURNING *`;
  const result = await pool.query(query, [...values, clienteId]);
  return result.rows[0];
};

export const getClientes = async () => {
  const result = await pool.query('SELECT * FROM clientes WHERE activo = true');
  return result.rows;
};

// Helper para construir consultas UPDATE dinámicas
function buildUpdateQuery(data) {
  const columns = [];
  const values = [];
  let paramIndex = 1;

  for (const [key, value] of Object.entries(data)) {
    if (value !== undefined) {
      columns.push(`${key} = $${paramIndex}`);
      values.push(value);
      paramIndex++;
    }
  }

  return {
    columns: columns.join(', '),
    values
  };
}