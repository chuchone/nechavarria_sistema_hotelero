CREATE OR REPLACE PROCEDURE sp_registrar_pago(
    p_reservacion_id INTEGER,
    p_monto NUMERIC(10,2),
    p_metodo_pago VARCHAR(50),
    p_referencia VARCHAR(100),
    p_descripcion TEXT,
    OUT p_pago_id INTEGER,
    OUT p_estado_reservacion VARCHAR(20),
    OUT p_mensaje TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_reserva NUMERIC(10,2) := 0;
    v_total_pagado NUMERIC(10,2) := 0;
    v_saldo_pendiente NUMERIC(10,2) := 0;
    v_estado_actual VARCHAR(20);
BEGIN
    -- Verificar y bloquear reservación para evitar condiciones de carrera
    SELECT estado INTO v_estado_actual
    FROM reservaciones
    WHERE reservacion_id = p_reservacion_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        p_mensaje := 'Reservación no encontrada';
        RETURN;
    END IF;
    
    -- Calcular total de la reserva
    SELECT COALESCE(SUM(rh.tarifa_aplicada * 
           (r.fecha_salida - r.fecha_entrada)), 0)
    INTO v_total_reserva
    FROM reservaciones r
    JOIN reservacion_habitaciones rh ON r.reservacion_id = rh.reservacion_id
    WHERE r.reservacion_id = p_reservacion_id;
    
    -- Calcular total ya pagado
    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_pagado
    FROM pagos
    WHERE reservacion_id = p_reservacion_id
    AND estado = 'completado';
    
    -- Validar monto de pago
    v_saldo_pendiente := v_total_reserva - v_total_pagado;
    
    IF p_monto <= 0 THEN
        p_mensaje := 'El monto del pago debe ser positivo';
        RETURN;
    END IF;
    
    IF p_monto > v_saldo_pendiente THEN
        p_mensaje := 'El monto excede el saldo pendiente. Saldo actual: ' || v_saldo_pendiente;
        RETURN;
    END IF;
    
    -- Registrar el pago
    INSERT INTO pagos (
        reservacion_id,
        monto,
        metodo_pago,
        estado,
        referencia,
        descripcion,
        fecha_pago
    ) VALUES (
        p_reservacion_id,
        p_monto,
        p_metodo_pago,
        'completado',
        p_referencia,
        p_descripcion,
        COALESCE(p_fecha_pago, CURRENT_TIMESTAMP)
    ) RETURNING pago_id INTO p_pago_id;
    
    -- Actualizar estado de la reservación si está completamente pagada
    IF (v_total_pagado + p_monto) >= v_total_reserva THEN
        UPDATE reservaciones
        SET estado = 'confirmada',
            fecha_confirmacion = CURRENT_TIMESTAMP
        WHERE reservacion_id = p_reservacion_id
        RETURNING estado INTO p_estado_reservacion;
        
        p_mensaje := 'Pago registrado exitosamente. Reservación confirmada.';
    ELSE
        p_estado_reservacion := v_estado_actual;
        p_mensaje := 'Pago registrado exitosamente. Saldo pendiente: ' || (v_saldo_pendiente - p_monto);
    END IF;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_mensaje := 'Error al registrar pago: ' || SQLERRM;
END;
$$;



CREATE OR REPLACE FUNCTION fn_listar_pagos(
    p_id_cliente INTEGER DEFAULT NULL,
    p_fecha_desde TIMESTAMP DEFAULT NULL,
    p_fecha_hasta TIMESTAMP DEFAULT NULL,
    p_metodo_pago VARCHAR(50) DEFAULT NULL,
    p_estado VARCHAR(20) DEFAULT NULL
)
RETURNS TABLE (
    pago_id INTEGER,
    reservacion_id INTEGER,
    cliente_id INTEGER,
    cliente_nombre VARCHAR(100),
    monto NUMERIC(10,2),
    metodo_pago VARCHAR(50),
    fecha_pago TIMESTAMP,
    estado VARCHAR(20),
    referencia VARCHAR(100)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.pago_id,
        p.reservacion_id,
        r.cliente_id,
        c.nombre AS cliente_nombre,
        p.monto,
        p.metodo_pago,
        p.fecha_pago,
        p.estado,
        p.referencia
    FROM pagos p
    JOIN reservaciones r ON p.reservacion_id = r.reservacion_id
    JOIN clientes c ON r.cliente_id = c.cliente_id
    WHERE (p_id_cliente IS NULL OR r.cliente_id = p_id_cliente)
      AND (p_fecha_desde IS NULL OR p.fecha_pago >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR p.fecha_pago <= p_fecha_hasta)
      AND (p_metodo_pago IS NULL OR p.metodo_pago = p_metodo_pago)
      AND (p_estado IS NULL OR p.estado = p_estado)
    ORDER BY p.fecha_pago DESC;
END;
$$;



CREATE OR REPLACE FUNCTION fn_obtener_pago(
    p_pago_id INTEGER
)
RETURNS TABLE (
    pago_id INTEGER,
    reservacion_id INTEGER,
    monto NUMERIC(10,2),
    metodo_pago VARCHAR(50),
    fecha_pago TIMESTAMP,
    estado VARCHAR(20),
    referencia VARCHAR(100),
    descripcion TEXT,
    datos_reservacion JSONB
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.pago_id,
        p.reservacion_id,
        p.monto,
        p.metodo_pago,
        p.fecha_pago,
        p.estado,
        p.referencia,
        p.descripcion,
        jsonb_build_object(
            'cliente_id', r.cliente_id,
            'fecha_entrada', r.fecha_entrada,
            'fecha_salida', r.fecha_salida,
            'estado_reservacion', r.estado,
            'total_reserva', (
                SELECT SUM(rh.tarifa_aplicada * (r.fecha_salida - r.fecha_entrada))
                FROM reservacion_habitaciones rh
                WHERE rh.reservacion_id = r.reservacion_id
            )
        ) AS datos_reservacion
    FROM pagos p
    JOIN reservaciones r ON p.reservacion_id = r.reservacion_id
    WHERE p.pago_id = p_pago_id;
END;
$$;