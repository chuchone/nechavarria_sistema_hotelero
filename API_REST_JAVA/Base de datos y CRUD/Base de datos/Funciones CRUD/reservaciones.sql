CREATE OR REPLACE PROCEDURE sp_crear_reservacion(
    p_id_cliente INTEGER,
    p_id_habitacion INTEGER,
    p_fecha_entrada DATE,
    p_fecha_salida DATE,
    p_numero_huespedes INTEGER,
    p_solicitudes_especiales TEXT,
    p_tarifa_aplicada NUMERIC(10,2),
    OUT p_reservacion_id INTEGER,
    OUT p_resultado TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_disponible BOOLEAN;
    v_habitacion_bloqueada BOOLEAN := FALSE;
BEGIN
    -- Verificar disponibilidad con bloqueo de fila
    BEGIN
        SELECT NOT EXISTS (
            SELECT 1 FROM reservacion_habitaciones rh
            JOIN reservaciones r ON rh.reservacion_id = r.reservacion_id
            WHERE rh.habitacion_id = p_id_habitacion
            AND r.estado NOT IN ('cancelada', 'finalizada')
            AND (r.fecha_entrada, r.fecha_salida) OVERLAPS (p_fecha_entrada, p_fecha_salida)
            FOR UPDATE OF rh NOWAIT
        ) INTO v_disponible;
    EXCEPTION WHEN lock_not_available THEN
        v_habitacion_bloqueada := TRUE;
    END;
    
    IF v_habitacion_bloqueada THEN
        p_resultado := 'La habitación está siendo procesada por otro usuario. Intente nuevamente.';
        RETURN;
    END IF;
    
    IF NOT v_disponible THEN
        p_resultado := 'La habitación no está disponible para las fechas seleccionadas.';
        RETURN;
    END IF;
    
 
    INSERT INTO reservaciones (
        cliente_id, 
        fecha_entrada, 
        fecha_salida, 
        huespedes, 
        solicitudes_especiales,
        estado,
        fecha_creacion
    ) VALUES (
        p_id_cliente,
        p_fecha_entrada,
        p_fecha_salida,
        p_numero_huespedes,
        p_solicitudes_especiales,
        'pendiente',
        CURRENT_TIMESTAMP
    ) RETURNING reservacion_id INTO p_reservacion_id;
    

    INSERT INTO reservacion_habitaciones (
        reservacion_id,
        habitacion_id,
        tarifa_aplicada,
        notas
    ) VALUES (
        p_reservacion_id,
        p_id_habitacion,
        p_tarifa_aplicada,
        'Reservación inicial'
    );
    
    p_resultado := 'Reservación creada exitosamente con ID: ' || p_reservacion_id;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'Error al crear reservación: ' || SQLERRM;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_actualizar_reservacion(
    p_reservacion_id INTEGER,
    p_fecha_entrada DATE,
    p_fecha_salida DATE,
    p_numero_huespedes INTEGER,
    p_solicitudes_especiales TEXT,
    p_version INTEGER, -- Campo de versión para OCC
    OUT p_resultado TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_version INTEGER;
    v_habitacion_id INTEGER;
    v_disponible BOOLEAN;
BEGIN
    -- Obtener versión actual y habitación asociada
    SELECT version, habitacion_id INTO v_current_version, v_habitacion_id
    FROM reservaciones r
    JOIN reservacion_habitaciones rh ON r.reservacion_id = rh.reservacion_id
    WHERE r.reservacion_id = p_reservacion_id
    FOR UPDATE;
    
    -- Verificar concurrencia optimista
    IF v_current_version != p_version THEN
        p_resultado := 'La reservación ha sido modificada por otro usuario. Por favor refresque los datos.';
        RETURN;
    END IF;
    
    -- Verificar disponibilidad si cambian las fechas
    IF (p_fecha_entrada, p_fecha_salida) != (
        SELECT fecha_entrada, fecha_salida FROM reservaciones 
        WHERE reservacion_id = p_reservacion_id
    ) THEN
        SELECT NOT EXISTS (
            SELECT 1 FROM reservacion_habitaciones rh
            JOIN reservaciones r ON rh.reservacion_id = r.reservacion_id
            WHERE rh.habitacion_id = v_habitacion_id
            AND r.reservacion_id != p_reservacion_id
            AND r.estado NOT IN ('cancelada', 'finalizada')
            AND (r.fecha_entrada, r.fecha_salida) OVERLAPS (p_fecha_entrada, p_fecha_salida)
        ) INTO v_disponible;
        
        IF NOT v_disponible THEN
            p_resultado := 'La habitación no está disponible para las nuevas fechas seleccionadas.';
            RETURN;
        END IF;
    END IF;
    
    -- Actualizar reservación
    UPDATE reservaciones
    SET 
        fecha_entrada = p_fecha_entrada,
        fecha_salida = p_fecha_salida,
        numero_huespedes = p_numero_huespedes,
        solicitudes_especiales = p_solicitudes_especiales,
        version = version + 1,
        fecha_actualizacion = CURRENT_TIMESTAMP
    WHERE reservacion_id = p_reservacion_id;
    
    p_resultado := 'Reservación actualizada exitosamente';
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'Error al actualizar reservación: ' || SQLERRM;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_cancelar_reservacion(
    p_reservacion_id INTEGER,
    p_motivo TEXT,
    OUT p_reembolso NUMERIC(10,2),
    OUT p_resultado TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_actual VARCHAR(20);
    v_fecha_entrada DATE;
    v_pagos_completados NUMERIC(10,2) := 0;
    v_tarifa_total NUMERIC(10,2);
    v_porcentaje_penalidad NUMERIC(5,2) := 0;
BEGIN
    
    SELECT r.estado, r.fecha_entrada, 
           COALESCE(SUM(p.monto), 0)
    INTO v_estado_actual, v_fecha_entrada, v_pagos_completados
    FROM reservaciones r
    LEFT JOIN pagos p ON r.reservacion_id = p.reservacion_id AND p.estado = 'completado'
    WHERE r.reservacion_id = p_reservacion_id
    GROUP BY r.reservacion_id, r.estado, r.fecha_entrada
    FOR UPDATE;
    
    IF NOT FOUND THEN
        p_resultado := 'Reservación no encontrada';
        RETURN;
    END IF;
    
    IF v_estado_actual = 'cancelada' THEN
        p_resultado := 'La reservación ya estaba cancelada';
        p_reembolso := 0;
        RETURN;
    END IF;
    
    SELECT SUM(rh.tarifa_aplicada * 
           (r.fecha_salida - r.fecha_entrada))
    INTO v_tarifa_total
    FROM reservaciones r
    JOIN reservacion_habitaciones rh ON r.reservacion_id = rh.reservacion_id
    WHERE r.reservacion_id = p_reservacion_id;
    
    IF CURRENT_DATE >= (v_fecha_entrada - INTERVAL '7 days') THEN
        v_porcentaje_penalidad := 0.50; 
    ELSIF CURRENT_DATE >= (v_fecha_entrada - INTERVAL '30 days') THEN
        v_porcentaje_penalidad := 0.20; 
    END IF;
    
    p_reembolso := GREATEST(0, v_pagos_completados - (v_tarifa_total * v_porcentaje_penalidad));
    
    UPDATE reservaciones
    SET estado = 'cancelada',
        fecha_cancelacion = CURRENT_TIMESTAMP,
        motivo_cancelacion = p_motivo
    WHERE reservacion_id = p_reservacion_id;
    
    IF p_reembolso < v_pagos_completados THEN
        INSERT INTO pagos (
            reservacion_id,
            monto,
            metodo_pago,
            estado,
            descripcion
        ) VALUES (
            p_reservacion_id,
            v_pagos_completados - p_reembolso,
            'reembolso',
            'reembolsado',
            'Penalidad por cancelación: ' || p_motivo
        );
    END IF;
    
    IF p_reembolso > 0 THEN
        INSERT INTO pagos (
            reservacion_id,
            monto,
            metodo_pago,
            estado,
            descripcion
        ) VALUES (
            p_reservacion_id,
            p_reembolso,
            'reembolso',
            'reembolsado',
            'Reembolso por cancelación: ' || p_motivo
        );
    END IF;
    
    p_resultado := 'Reservación cancelada exitosamente. Reembolso: ' || p_reembolso;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'Error al cancelar reservación: ' || SQLERRM;
        p_reembolso := 0;
END;
$$;
