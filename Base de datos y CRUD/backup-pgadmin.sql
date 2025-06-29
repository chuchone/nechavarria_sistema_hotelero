--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.2

-- Started on 2025-06-29 09:51:50

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: azure_pg_admin
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO azure_pg_admin;

--
-- TOC entry 250 (class 1255 OID 25602)
-- Name: actualizar_estado_pago(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.actualizar_estado_pago(p_pago_id integer, p_estado character varying, p_usuario character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Validar estado
    IF p_estado NOT IN ('pendiente', 'completado', 'reembolsado', 'fallido') THEN
        RAISE EXCEPTION 'Estado de pago no valido';
    END IF;
    
    -- Actualizar estado del pago (el trigger manejar¶ÿ la actualizaci¶¢n de la reserva)
    UPDATE pagos
    SET estado = p_estado
    WHERE pago_id = p_pago_id;
    
    -- Registrar en bit¶ÿcora
    PERFORM registrar_bitacora(
        p_usuario, 
        'ACTUALIZACION', 
        'pagos', 
        p_pago_id, 
        'Estado de pago actualizado a: ' || p_estado,
        inet_client_addr()::TEXT
    );
END;
$$;


ALTER FUNCTION public.actualizar_estado_pago(p_pago_id integer, p_estado character varying, p_usuario character varying) OWNER TO nechavarria;

--
-- TOC entry 255 (class 1255 OID 25603)
-- Name: bitacora_pagos_trigger(); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.bitacora_pagos_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'CREACION', 
            'pagos', 
            NEW.pago_id, 
            'Nuevo pago registrado. Monto: ' || NEW.monto || ', Mƒ??todo: ' || NEW.metodo_pago,
            inet_client_addr()::TEXT
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.estado != NEW.estado THEN
            PERFORM registrar_bitacora(
                CURRENT_USER, 
                'ACTUALIZACION', 
                'pagos', 
                NEW.pago_id, 
                'Estado de pago cambiado de ' || OLD.estado || ' a ' || NEW.estado,
                inet_client_addr()::TEXT
            );
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'ELIMINACION', 
            'pagos', 
            OLD.pago_id, 
            'Pago eliminado',
            inet_client_addr()::TEXT
        );
    END IF;
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION public.bitacora_pagos_trigger() OWNER TO nechavarria;

--
-- TOC entry 277 (class 1255 OID 25605)
-- Name: cancelacion_reservacion_trigger(); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.cancelacion_reservacion_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_dias_restantes INTEGER;
    v_hotel_nombre VARCHAR(100);
    v_cliente_nombre VARCHAR(100);
    v_habitaciones TEXT;
BEGIN
    -- Solo actuar cuando el estado cambia a 'cancelada'
    IF NEW.estado = 'cancelada' AND OLD.estado != 'cancelada' THEN
        -- Calcular d¶¡as restantes hasta la fecha de entrada
        v_dias_restantes := NEW.fecha_entrada - CURRENT_DATE;
        
        -- Registrar en bit¶ÿcora
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'CANCELACION', 
            'reservaciones', 
            NEW.reservacion_id, 
            'Reserva cancelada. D¶¡as restantes: ' || v_dias_restantes,
            inet_client_addr()::TEXT
        );
        
        -- Enviar alerta si es cancelaci¶¢n de ¶£ltima hora (menos de 3 d¶¡as)
        IF v_dias_restantes < 3 THEN
            -- Obtener informaci¶¢n para la alerta
            SELECT nombre INTO v_hotel_nombre FROM hoteles WHERE hotel_id = NEW.hotel_id;
            SELECT nombre INTO v_cliente_nombre FROM clientes WHERE cliente_id = NEW.cliente_id;
            
            -- Registrar alerta en bit¶ÿcora
            PERFORM registrar_bitacora(
                CURRENT_USER, 
                'ALERTA', 
                'reservaciones', 
                NEW.reservacion_id, 
                'ALERTA: Cancelaci¶¢n de ultima hora. Cliente: ' || v_cliente_nombre || ', Hotel: ' || v_hotel_nombre,
                inet_client_addr()::TEXT
            );
            
            -- Aqu¶¡ podr¶¡as agregar l¶¢gica para enviar email/notificaci¶¢n
            RAISE NOTICE 'ALERTA: Cancelacion de uultima hora. Reservacion ID: %, Cliente: %, Hotel: %', 
                         NEW.reservacion_id, v_cliente_nombre, v_hotel_nombre;
        END IF;
        
        -- Liberar habitaciones asociadas
        UPDATE habitaciones h
        SET estado = 'disponible'
        FROM reservacion_habitaciones rh
        WHERE rh.habitacion_id = h.habitacion_id
        AND rh.reservacion_id = NEW.reservacion_id;
        
        -- Registrar liberaci¶¢n en bit¶ÿcora
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'ACTUALIZACION', 
            'habitaciones', 
            NEW.reservacion_id, 
            'Habitaciones liberadas por cancelaci¶¢n de reserva',
            inet_client_addr()::TEXT
        );
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.cancelacion_reservacion_trigger() OWNER TO nechavarria;

--
-- TOC entry 278 (class 1255 OID 25606)
-- Name: cancelar_reservacion(integer, character varying, text); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.cancelar_reservacion(p_reservacion_id integer, p_usuario character varying, p_razon text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_actual VARCHAR;
BEGIN
    -- Obtener estado actual
    SELECT estado INTO v_estado_actual FROM reservaciones WHERE reservacion_id = p_reservacion_id;
    
    IF v_estado_actual IS NULL THEN
        RAISE EXCEPTION 'Reservaci¶¢n no encontrada';
    END IF;
    
    IF v_estado_actual = 'cancelada' THEN
        RAISE NOTICE 'La reservaci¶¢n ya est¶ÿ cancelada';
        RETURN;
    END IF;
    
    -- Actualizar estado a cancelada
    UPDATE reservaciones 
    SET estado = 'cancelada'
    WHERE reservacion_id = p_reservacion_id;
    
    -- Registrar en bit¶ÿcora (el trigger manejar¶ÿ la liberaci¶¢n de habitaciones)
    PERFORM registrar_bitacora(
        p_usuario, 
        'CANCELACION', 
        'reservaciones', 
        p_reservacion_id, 
        'Reserva cancelada. Raz¶¢n: ' || COALESCE(p_razon, 'No especificada'),
        inet_client_addr()::TEXT
    );
END;
$$;


ALTER FUNCTION public.cancelar_reservacion(p_reservacion_id integer, p_usuario character varying, p_razon text) OWNER TO nechavarria;

--
-- TOC entry 279 (class 1255 OID 25607)
-- Name: crear_reservacion(integer, integer, date, date, integer, integer, character varying, text, character varying, character varying, jsonb); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.crear_reservacion(p_hotel_id integer, p_cliente_id integer, p_fecha_entrada date, p_fecha_salida date, p_adultos integer, p_ninos integer DEFAULT 0, p_tipo_reserva character varying DEFAULT 'individual'::character varying, p_solicitudes_especiales text DEFAULT NULL::text, p_usuario character varying DEFAULT CURRENT_USER, p_ip_origen character varying DEFAULT (inet_client_addr())::text, p_tipos_habitaciones jsonb DEFAULT '[{"tipo_id": 1, "cantidad": 1}]'::jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_reservacion_id INTEGER;
    v_codigo_reserva VARCHAR(20);
    v_item JSONB;
    v_habitacion RECORD;
    v_disponibles INTEGER;
    v_tarifa DECIMAL(10, 2);
BEGIN
    -- Validaciones iniciales
    IF p_fecha_salida <= p_fecha_entrada THEN
        RAISE EXCEPTION 'La fecha de salida debe ser posterior a la fecha de entrada';
    END IF;
    
    IF p_adultos < 1 THEN
        RAISE EXCEPTION 'Debe haber al menos un adulto en la reservacion';
    END IF;
    
    -- Verificar disponibilidad para cada tipo de habitaci¶¢n solicitada
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_tipos_habitaciones) LOOP
        -- Verificar que exista el tipo de habitaci¶¢n en el hotel
        PERFORM 1 FROM tipos_habitacion 
        WHERE tipo_id = (v_item->>'tipo_id')::INTEGER AND hotel_id = p_hotel_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El tipo de habitacion % no existe en este hotel', (v_item->>'tipo_id');
        END IF;
        
        -- Contar habitaciones disponibles
        SELECT COUNT(*) INTO v_disponibles
        FROM verificar_disponibilidad(
            p_hotel_id,
            (v_item->>'tipo_id')::INTEGER,
            p_fecha_entrada,
            p_fecha_salida
        );
        
        IF v_disponibles < (v_item->>'cantidad')::INTEGER THEN
            RAISE EXCEPTION 'No hay suficientes habitaciones disponibles del tipo %', (v_item->>'tipo_id');
        END IF;
    END LOOP;
    
    -- Generar c¶¢digo de reserva ¶£nico
    v_codigo_reserva := 'RES-' || p_hotel_id || '-' || 
                        EXTRACT(YEAR FROM CURRENT_DATE) || '-' || 
                        LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    
    -- Crear la reservaci¶¢n principal
    INSERT INTO reservaciones (
        hotel_id,
        cliente_id,
        fecha_entrada,
        fecha_salida,
        adultos,
        ninos,
        estado,
        tipo_reserva,
        solicitudes_especiales,
        codigo_reserva
    ) VALUES (
        p_hotel_id,
        p_cliente_id,
        p_fecha_entrada,
        p_fecha_salida,
        p_adultos,
        p_ninos,
        'confirmada', -- Estado inicial
        p_tipo_reserva,
        p_solicitudes_especiales,
        v_codigo_reserva
    ) RETURNING reservacion_id INTO v_reservacion_id;
    
    -- Asignar habitaciones espec¶¡ficas
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_tipos_habitaciones) LOOP
        -- Obtener tarifa aplicable
        SELECT COALESCE(
            (SELECT t.precio 
             FROM tarifas_temporada t 
             JOIN politicas_temporada p ON t.politica_id = p.politica_id
             WHERE t.tipo_id = (v_item->>'tipo_id')::INTEGER
             AND p.fecha_inicio <= p_fecha_entrada 
             AND p.fecha_fin >= p_fecha_salida
             LIMIT 1),
            (SELECT precio_base FROM tipos_habitacion WHERE tipo_id = (v_item->>'tipo_id')::INTEGER)
        ) INTO v_tarifa;
        
        -- Asignar habitaciones disponibles
        FOR v_habitacion IN 
            SELECT * FROM verificar_disponibilidad(
                p_hotel_id,
                (v_item->>'tipo_id')::INTEGER,
                p_fecha_entrada,
                p_fecha_salida
            ) LIMIT (v_item->>'cantidad')::INTEGER
        LOOP
            -- Asignar habitaci¶¢n a la reservaci¶¢n
            INSERT INTO reservacion_habitaciones (
                reservacion_id,
                habitacion_id,
                tarifa_aplicada,
                notas
            ) VALUES (
                v_reservacion_id,
                v_habitacion.habitacion_id,
                v_tarifa,
                'Asignaci¶¢n inicial'
            );
            
            -- Marcar habitaci¶¢n como ocupada
            UPDATE habitaciones 
            SET estado = 'ocupada' 
            WHERE habitacion_id = v_habitacion.habitacion_id;
        END LOOP;
    END LOOP;
    
    -- Registrar en bit¶ÿcora
    PERFORM registrar_bitacora(
        p_usuario,
        'CREACION',
        'reservaciones',
        v_reservacion_id,
        'Reserva creada con c¶¢digo ' || v_codigo_reserva,
        p_ip_origen
    );
    
    RETURN v_reservacion_id;
END;
$$;


ALTER FUNCTION public.crear_reservacion(p_hotel_id integer, p_cliente_id integer, p_fecha_entrada date, p_fecha_salida date, p_adultos integer, p_ninos integer, p_tipo_reserva character varying, p_solicitudes_especiales text, p_usuario character varying, p_ip_origen character varying, p_tipos_habitaciones jsonb) OWNER TO nechavarria;

--
-- TOC entry 287 (class 1255 OID 25697)
-- Name: fn_listar_pagos(integer, timestamp without time zone, timestamp without time zone, character varying, character varying); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.fn_listar_pagos(p_id_cliente integer DEFAULT NULL::integer, p_fecha_desde timestamp without time zone DEFAULT NULL::timestamp without time zone, p_fecha_hasta timestamp without time zone DEFAULT NULL::timestamp without time zone, p_metodo_pago character varying DEFAULT NULL::character varying, p_estado character varying DEFAULT NULL::character varying) RETURNS TABLE(pago_id integer, reservacion_id integer, cliente_id integer, cliente_nombre character varying, monto numeric, metodo_pago character varying, fecha_pago timestamp without time zone, estado character varying, referencia character varying)
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


ALTER FUNCTION public.fn_listar_pagos(p_id_cliente integer, p_fecha_desde timestamp without time zone, p_fecha_hasta timestamp without time zone, p_metodo_pago character varying, p_estado character varying) OWNER TO nechavarria;

--
-- TOC entry 283 (class 1255 OID 25692)
-- Name: fn_obtener_pago(integer); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.fn_obtener_pago(p_pago_id integer) RETURNS TABLE(pago_id integer, reservacion_id integer, monto numeric, metodo_pago character varying, fecha_pago timestamp without time zone, estado character varying, referencia character varying, descripcion text, datos_reservacion jsonb)
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


ALTER FUNCTION public.fn_obtener_pago(p_pago_id integer) OWNER TO nechavarria;

--
-- TOC entry 280 (class 1255 OID 25609)
-- Name: pago_registrado_trigger(); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.pago_registrado_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Solo actuar cuando el pago se marca como completado
    IF NEW.estado = 'completado' AND OLD.estado != 'completado' THEN
        -- Actualizar estado de la reservaci¶¢n a 'confirmada'
        UPDATE reservaciones
        SET estado = 'confirmada'
        WHERE reservacion_id = NEW.reservacion_id;
        
        -- Registrar en bit¶ÿcora
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'CONFIRMACION', 
            'reservaciones', 
            NEW.reservacion_id, 
            'Reserva confirmada por pago completado. Pago ID: ' || NEW.pago_id,
            inet_client_addr()::TEXT
        );
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.pago_registrado_trigger() OWNER TO nechavarria;

--
-- TOC entry 254 (class 1255 OID 25680)
-- Name: registrar_bitacora(character varying, character varying, character varying, integer, text, character varying); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.registrar_bitacora(p_usuario character varying, p_accion character varying, p_tabla character varying, p_id_registro integer, p_detalles text, p_ip character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO bitacora_reservaciones (
        usuario,
        accion,
        tabla_afectada,
        id_registro,
        detalles,
        direccion_ip
    ) VALUES (
        p_usuario,
        p_accion,
        p_tabla,
        p_id_registro,
        p_detalles,
        p_ip
    );
END;
$$;


ALTER FUNCTION public.registrar_bitacora(p_usuario character varying, p_accion character varying, p_tabla character varying, p_id_registro integer, p_detalles text, p_ip character varying) OWNER TO nechavarria;

--
-- TOC entry 284 (class 1255 OID 25694)
-- Name: sp_actualizar_reservacion(integer, date, date, integer, text, integer); Type: PROCEDURE; Schema: public; Owner: nechavarria
--

CREATE PROCEDURE public.sp_actualizar_reservacion(IN p_reservacion_id integer, IN p_fecha_entrada date, IN p_fecha_salida date, IN p_numero_huespedes integer, IN p_solicitudes_especiales text, IN p_version integer, OUT p_resultado text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_version INTEGER;
    v_habitacion_id INTEGER;
    v_disponible BOOLEAN;
BEGIN
    -- Obtener versi¢n actual y habitaci¢n asociada
    SELECT version, habitacion_id INTO v_current_version, v_habitacion_id
    FROM reservaciones r
    JOIN reservacion_habitaciones rh ON r.reservacion_id = rh.reservacion_id
    WHERE r.reservacion_id = p_reservacion_id
    FOR UPDATE;
    
    -- Verificar concurrencia optimista
    IF v_current_version != p_version THEN
        p_resultado := 'La reservaci¢n ha sido modificada por otro usuario. Por favor refresque los datos.';
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
            p_resultado := 'La habitaci¢n no est  disponible para las nuevas fechas seleccionadas.';
            RETURN;
        END IF;
    END IF;
    
    -- Actualizar reservaci¢n
    UPDATE reservaciones
    SET 
        fecha_entrada = p_fecha_entrada,
        fecha_salida = p_fecha_salida,
        numero_huespedes = p_numero_huespedes,
        solicitudes_especiales = p_solicitudes_especiales,
        version = version + 1,
        fecha_actualizacion = CURRENT_TIMESTAMP
    WHERE reservacion_id = p_reservacion_id;
    
    p_resultado := 'Reservaci¢n actualizada exitosamente';
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'Error al actualizar reservaci¢n: ' || SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_actualizar_reservacion(IN p_reservacion_id integer, IN p_fecha_entrada date, IN p_fecha_salida date, IN p_numero_huespedes integer, IN p_solicitudes_especiales text, IN p_version integer, OUT p_resultado text) OWNER TO nechavarria;

--
-- TOC entry 285 (class 1255 OID 25695)
-- Name: sp_cancelar_reservacion(integer, text); Type: PROCEDURE; Schema: public; Owner: nechavarria
--

CREATE PROCEDURE public.sp_cancelar_reservacion(IN p_reservacion_id integer, IN p_motivo text, OUT p_reembolso numeric, OUT p_resultado text)
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
        p_resultado := 'Reservaci¢n no encontrada';
        RETURN;
    END IF;
    
    IF v_estado_actual = 'cancelada' THEN
        p_resultado := 'La reservaci¢n ya estaba cancelada';
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
            'Penalidad por cancelaci¢n: ' || p_motivo
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
            'Reembolso por cancelaci¢n: ' || p_motivo
        );
    END IF;
    
    p_resultado := 'Reservaci¢n cancelada exitosamente. Reembolso: ' || p_reembolso;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'Error al cancelar reservaci¢n: ' || SQLERRM;
        p_reembolso := 0;
END;
$$;


ALTER PROCEDURE public.sp_cancelar_reservacion(IN p_reservacion_id integer, IN p_motivo text, OUT p_reembolso numeric, OUT p_resultado text) OWNER TO nechavarria;

--
-- TOC entry 288 (class 1255 OID 25698)
-- Name: sp_crear_reservacion(integer, integer, date, date, integer, text, numeric); Type: PROCEDURE; Schema: public; Owner: nechavarria
--

CREATE PROCEDURE public.sp_crear_reservacion(IN p_id_cliente integer, IN p_id_habitacion integer, IN p_fecha_entrada date, IN p_fecha_salida date, IN p_numero_huespedes integer, IN p_solicitudes_especiales text, IN p_tarifa_aplicada numeric, OUT p_reservacion_id integer, OUT p_resultado text)
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
        p_resultado := 'La habitaci¢n est  siendo procesada por otro usuario. Intente nuevamente.';
        RETURN;
    END IF;
    
    IF NOT v_disponible THEN
        p_resultado := 'La habitaci¢n no est  disponible para las fechas seleccionadas.';
        RETURN;
    END IF;

    INSERT INTO reservaciones (
        cliente_id, 
        fecha_entrada, 
        fecha_salida, 
        huespedes,
        solicitudes_especiales,
        estado,
        fecha_creacion,
        tipo_reserva
    ) VALUES (
        p_id_cliente,
        p_fecha_entrada,
        p_fecha_salida,
        p_numero_huespedes,
        p_solicitudes_especiales,
        'pendiente',
        CURRENT_TIMESTAMP,
        'individual'
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
        'Reservaci¢n inicial'
    );
    
    p_resultado := 'Reservaci¢n creada exitosamente con ID: ' || p_reservacion_id;

EXCEPTION
    WHEN OTHERS THEN
        p_resultado := 'Error al crear reservaci¢n: ' || SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_crear_reservacion(IN p_id_cliente integer, IN p_id_habitacion integer, IN p_fecha_entrada date, IN p_fecha_salida date, IN p_numero_huespedes integer, IN p_solicitudes_especiales text, IN p_tarifa_aplicada numeric, OUT p_reservacion_id integer, OUT p_resultado text) OWNER TO nechavarria;

--
-- TOC entry 286 (class 1255 OID 25696)
-- Name: sp_registrar_pago(integer, numeric, character varying, character varying, text); Type: PROCEDURE; Schema: public; Owner: nechavarria
--

CREATE PROCEDURE public.sp_registrar_pago(IN p_reservacion_id integer, IN p_monto numeric, IN p_metodo_pago character varying, IN p_referencia character varying, IN p_descripcion text, OUT p_pago_id integer, OUT p_estado_reservacion character varying, OUT p_mensaje text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_reserva NUMERIC(10,2) := 0;
    v_total_pagado NUMERIC(10,2) := 0;
    v_saldo_pendiente NUMERIC(10,2) := 0;
    v_estado_actual VARCHAR(20);
BEGIN
    -- Verificar y bloquear reservaci¢n para evitar condiciones de carrera
    SELECT estado INTO v_estado_actual
    FROM reservaciones
    WHERE reservacion_id = p_reservacion_id
    FOR UPDATE;
    
    IF NOT FOUND THEN
        p_mensaje := 'Reservaci¢n no encontrada';
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
    
    -- Actualizar estado de la reservaci¢n si est  completamente pagada
    IF (v_total_pagado + p_monto) >= v_total_reserva THEN
        UPDATE reservaciones
        SET estado = 'confirmada',
            fecha_confirmacion = CURRENT_TIMESTAMP
        WHERE reservacion_id = p_reservacion_id
        RETURNING estado INTO p_estado_reservacion;
        
        p_mensaje := 'Pago registrado exitosamente. Reservaci¢n confirmada.';
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


ALTER PROCEDURE public.sp_registrar_pago(IN p_reservacion_id integer, IN p_monto numeric, IN p_metodo_pago character varying, IN p_referencia character varying, IN p_descripcion text, OUT p_pago_id integer, OUT p_estado_reservacion character varying, OUT p_mensaje text) OWNER TO nechavarria;

--
-- TOC entry 282 (class 1255 OID 25681)
-- Name: tr_bitacora_reservaciones(); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.tr_bitacora_reservaciones() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_accion VARCHAR(20);
    v_detalles TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_accion := 'CREACION';
        v_detalles := 'Nueva reserva creada. ID: ' || NEW.reservacion_id || 
                     ', Estado: ' || NEW.estado || 
                     ', Fechas: ' || NEW.fecha_entrada || ' al ' || NEW.fecha_salida;
    ELSIF TG_OP = 'UPDATE' THEN
        v_accion := 'ACTUALIZACION';
        v_detalles := 'Reserva ID: ' || NEW.reservacion_id;
        
        IF OLD.estado != NEW.estado THEN
            v_detalles := v_detalles || '. Estado cambiado de ' || OLD.estado || ' a ' || NEW.estado;
        END IF;
        
        IF OLD.fecha_entrada != NEW.fecha_entrada OR OLD.fecha_salida != NEW.fecha_salida THEN
            v_detalles := v_detalles || '. Fechas modificadas de ' || OLD.fecha_entrada || '-' || OLD.fecha_salida ||
                         ' a ' || NEW.fecha_entrada || '-' || NEW.fecha_salida;
        END IF;
        
        IF OLD.hotel_id != NEW.hotel_id THEN
            v_detalles := v_detalles || '. Hotel cambiado de ' || OLD.hotel_id || ' a ' || NEW.hotel_id;
        END IF;
        
    ELSIF TG_OP = 'DELETE' THEN
        v_accion := 'ELIMINACION';
        v_detalles := 'Reserva eliminada. ID: ' || OLD.reservacion_id || 
                     ', Estado: ' || OLD.estado || 
                     ', Fechas: ' || OLD.fecha_entrada || ' al ' || OLD.fecha_salida;
    END IF;
    
    PERFORM registrar_bitacora(
        CURRENT_USER::VARCHAR(100), 
        v_accion, 
        'reservaciones'::VARCHAR(50), 
        COALESCE(NEW.reservacion_id, OLD.reservacion_id), 
        v_detalles,
        inet_client_addr()::TEXT
    );
    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION public.tr_bitacora_reservaciones() OWNER TO nechavarria;

--
-- TOC entry 281 (class 1255 OID 25612)
-- Name: verificar_disponibilidad(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: nechavarria
--

CREATE FUNCTION public.verificar_disponibilidad(p_hotel_id integer, p_tipo_id integer, p_fecha_entrada date, p_fecha_salida date) RETURNS TABLE(habitacion_id integer, numero character varying, piso integer, precio_recomendado numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT h.habitacion_id, h.numero, h.piso, 
           COALESCE(
               (SELECT t.precio 
                FROM tarifas_temporada t 
                JOIN politicas_temporada p ON t.politica_id = p.politica_id
                WHERE t.tipo_id = h.tipo_id 
                AND p.fecha_inicio <= p_fecha_entrada 
                AND p.fecha_fin >= p_fecha_salida
                LIMIT 1),
               th.precio_base
           ) AS precio_recomendado
    FROM habitaciones h
    JOIN tipos_habitacion th ON h.tipo_id = th.tipo_id
    WHERE h.hotel_id = p_hotel_id
    AND h.tipo_id = p_tipo_id
    AND h.estado = 'disponible'
    AND NOT EXISTS (
        SELECT 1 FROM reservacion_habitaciones rh
        JOIN reservaciones r ON rh.reservacion_id = r.reservacion_id
        WHERE rh.habitacion_id = h.habitacion_id
        AND r.estado NOT IN ('cancelada', 'no-show')
        AND (
            (r.fecha_entrada <= p_fecha_entrada AND r.fecha_salida > p_fecha_entrada) OR
            (r.fecha_entrada < p_fecha_salida AND r.fecha_salida >= p_fecha_salida) OR
            (r.fecha_entrada >= p_fecha_entrada AND r.fecha_salida <= p_fecha_salida)
        )
    );
END;
$$;


ALTER FUNCTION public.verificar_disponibilidad(p_hotel_id integer, p_tipo_id integer, p_fecha_entrada date, p_fecha_salida date) OWNER TO nechavarria;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 246 (class 1259 OID 25668)
-- Name: bitacora_reservaciones; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.bitacora_reservaciones (
    bitacora_id integer NOT NULL,
    usuario character varying(100) NOT NULL,
    accion character varying(20) NOT NULL,
    tabla_afectada character varying(50) NOT NULL,
    id_registro integer NOT NULL,
    detalles text,
    direccion_ip character varying(45),
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.bitacora_reservaciones OWNER TO nechavarria;

--
-- TOC entry 4335 (class 0 OID 0)
-- Dependencies: 246
-- Name: TABLE bitacora_reservaciones; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON TABLE public.bitacora_reservaciones IS 'Registro de todas las operaciones realizadas en la tabla reservaciones';


--
-- TOC entry 4336 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.usuario; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.usuario IS 'Usuario que realiz¢ la acci¢n';


--
-- TOC entry 4337 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.accion; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.accion IS 'Tipo de acci¢n realizada';


--
-- TOC entry 4338 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.tabla_afectada; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.tabla_afectada IS 'Tabla donde se realiz¢ el cambio';


--
-- TOC entry 4339 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.id_registro; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.id_registro IS 'ID del registro afectado';


--
-- TOC entry 4340 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.detalles; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.detalles IS 'Detalles espec¡ficos del cambio';


--
-- TOC entry 4341 (class 0 OID 0)
-- Dependencies: 246
-- Name: COLUMN bitacora_reservaciones.direccion_ip; Type: COMMENT; Schema: public; Owner: nechavarria
--

COMMENT ON COLUMN public.bitacora_reservaciones.direccion_ip IS 'Direcci¢n IP desde donde se realiz¢ la acci¢n';


--
-- TOC entry 245 (class 1259 OID 25667)
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.bitacora_reservaciones_bitacora_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bitacora_reservaciones_bitacora_id_seq OWNER TO nechavarria;

--
-- TOC entry 4342 (class 0 OID 0)
-- Dependencies: 245
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.bitacora_reservaciones_bitacora_id_seq OWNED BY public.bitacora_reservaciones.bitacora_id;


--
-- TOC entry 217 (class 1259 OID 25402)
-- Name: clientes; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.clientes (
    cliente_id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    documento_identidad character varying(20) NOT NULL,
    tipo_documento character varying(20) NOT NULL,
    nacionalidad character varying(50) NOT NULL,
    telefono character varying(20) NOT NULL,
    email character varying(100) NOT NULL,
    fecha_registro timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    activo boolean DEFAULT true,
    preferencias character varying(255),
    alergias character varying(255),
    password_hash character varying(255)
);


ALTER TABLE public.clientes OWNER TO nechavarria;

--
-- TOC entry 218 (class 1259 OID 25409)
-- Name: clientes_cliente_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.clientes_cliente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clientes_cliente_id_seq OWNER TO nechavarria;

--
-- TOC entry 4343 (class 0 OID 0)
-- Dependencies: 218
-- Name: clientes_cliente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.clientes_cliente_id_seq OWNED BY public.clientes.cliente_id;


--
-- TOC entry 219 (class 1259 OID 25410)
-- Name: facturas; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.facturas (
    factura_id integer NOT NULL,
    pago_id integer,
    hotel_id integer,
    numero_factura character varying(50) NOT NULL,
    fecha_emision date NOT NULL,
    subtotal numeric(10,2) NOT NULL,
    impuestos numeric(10,2) NOT NULL,
    total numeric(10,2) NOT NULL,
    datos_cliente text NOT NULL,
    detalles text NOT NULL
);


ALTER TABLE public.facturas OWNER TO nechavarria;

--
-- TOC entry 220 (class 1259 OID 25415)
-- Name: facturas_factura_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.facturas_factura_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.facturas_factura_id_seq OWNER TO nechavarria;

--
-- TOC entry 4344 (class 0 OID 0)
-- Dependencies: 220
-- Name: facturas_factura_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.facturas_factura_id_seq OWNED BY public.facturas.factura_id;


--
-- TOC entry 221 (class 1259 OID 25416)
-- Name: fidelizacion_clientes; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.fidelizacion_clientes (
    fidelizacion_id integer NOT NULL,
    cliente_id integer,
    hotel_id integer,
    puntos_acumulados integer DEFAULT 0,
    nivel_membresia character varying(20),
    beneficios text,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.fidelizacion_clientes OWNER TO nechavarria;

--
-- TOC entry 222 (class 1259 OID 25423)
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq OWNER TO nechavarria;

--
-- TOC entry 4345 (class 0 OID 0)
-- Dependencies: 222
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq OWNED BY public.fidelizacion_clientes.fidelizacion_id;


--
-- TOC entry 223 (class 1259 OID 25424)
-- Name: habitaciones; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.habitaciones (
    habitacion_id integer NOT NULL,
    hotel_id integer DEFAULT 1,
    numero character varying(10) NOT NULL,
    tipo_id integer DEFAULT 3,
    piso integer DEFAULT 1 NOT NULL,
    caracteristicas_especiales text,
    estado character varying(20) NOT NULL,
    notas text,
    precio_habitacion numeric(10,2),
    esta_ocupada boolean DEFAULT false,
    descripcion character varying(100),
    CONSTRAINT habitaciones_estado_check CHECK (((estado)::text = ANY (ARRAY[('disponible'::character varying)::text, ('ocupada'::character varying)::text, ('mantenimiento'::character varying)::text, ('limpieza'::character varying)::text])))
);


ALTER TABLE public.habitaciones OWNER TO nechavarria;

--
-- TOC entry 224 (class 1259 OID 25430)
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.habitaciones_habitacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.habitaciones_habitacion_id_seq OWNER TO nechavarria;

--
-- TOC entry 4346 (class 0 OID 0)
-- Dependencies: 224
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.habitaciones_habitacion_id_seq OWNED BY public.habitaciones.habitacion_id;


--
-- TOC entry 225 (class 1259 OID 25431)
-- Name: historico_estadias; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.historico_estadias (
    historico_id integer NOT NULL,
    hotel_id integer,
    cliente_id integer,
    reservacion_id integer,
    fecha_entrada date NOT NULL,
    fecha_salida date NOT NULL,
    habitacion_id integer,
    comentarios text,
    calificacion integer,
    preferencias_registradas text,
    CONSTRAINT historico_estadias_calificacion_check CHECK (((calificacion >= 1) AND (calificacion <= 5)))
);


ALTER TABLE public.historico_estadias OWNER TO nechavarria;

--
-- TOC entry 226 (class 1259 OID 25437)
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.historico_estadias_historico_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historico_estadias_historico_id_seq OWNER TO nechavarria;

--
-- TOC entry 4347 (class 0 OID 0)
-- Dependencies: 226
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.historico_estadias_historico_id_seq OWNED BY public.historico_estadias.historico_id;


--
-- TOC entry 227 (class 1259 OID 25438)
-- Name: hoteles; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.hoteles (
    hotel_id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    direccion text NOT NULL,
    ciudad character varying(50) NOT NULL,
    pais character varying(50) NOT NULL,
    telefono character varying(20) NOT NULL,
    email character varying(100) NOT NULL,
    estrellas integer,
    activo boolean DEFAULT true,
    fecha_apertura date,
    descripcion text,
    CONSTRAINT hoteles_estrellas_check CHECK (((estrellas >= 1) AND (estrellas <= 5)))
);


ALTER TABLE public.hoteles OWNER TO nechavarria;

--
-- TOC entry 228 (class 1259 OID 25445)
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.hoteles_hotel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.hoteles_hotel_id_seq OWNER TO nechavarria;

--
-- TOC entry 4348 (class 0 OID 0)
-- Dependencies: 228
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.hoteles_hotel_id_seq OWNED BY public.hoteles.hotel_id;


--
-- TOC entry 229 (class 1259 OID 25446)
-- Name: pagos; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.pagos (
    pago_id integer NOT NULL,
    reservacion_id integer,
    monto numeric(10,2) NOT NULL,
    metodo_pago character varying(50) NOT NULL,
    fecha_pago timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    estado character varying(20) NOT NULL,
    referencia character varying(100),
    descripcion text,
    CONSTRAINT pagos_estado_check CHECK (((estado)::text = ANY (ARRAY[('pendiente'::character varying)::text, ('completado'::character varying)::text, ('reembolsado'::character varying)::text, ('fallido'::character varying)::text])))
);


ALTER TABLE public.pagos OWNER TO nechavarria;

--
-- TOC entry 230 (class 1259 OID 25453)
-- Name: pagos_pago_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.pagos_pago_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pagos_pago_id_seq OWNER TO nechavarria;

--
-- TOC entry 4349 (class 0 OID 0)
-- Dependencies: 230
-- Name: pagos_pago_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.pagos_pago_id_seq OWNED BY public.pagos.pago_id;


--
-- TOC entry 231 (class 1259 OID 25454)
-- Name: politicas_temporada; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.politicas_temporada (
    politica_id integer NOT NULL,
    hotel_id integer,
    nombre character varying(100) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    descripcion text,
    reglas text,
    CONSTRAINT fechas_validas CHECK ((fecha_fin > fecha_inicio))
);


ALTER TABLE public.politicas_temporada OWNER TO nechavarria;

--
-- TOC entry 232 (class 1259 OID 25460)
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.politicas_temporada_politica_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.politicas_temporada_politica_id_seq OWNER TO nechavarria;

--
-- TOC entry 4350 (class 0 OID 0)
-- Dependencies: 232
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.politicas_temporada_politica_id_seq OWNED BY public.politicas_temporada.politica_id;


--
-- TOC entry 233 (class 1259 OID 25461)
-- Name: reservacion_habitaciones; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.reservacion_habitaciones (
    detalle_id integer NOT NULL,
    reservacion_id integer,
    habitacion_id integer,
    tarifa_aplicada numeric(10,2) NOT NULL,
    notas text
);


ALTER TABLE public.reservacion_habitaciones OWNER TO nechavarria;

--
-- TOC entry 234 (class 1259 OID 25466)
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.reservacion_habitaciones_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservacion_habitaciones_detalle_id_seq OWNER TO nechavarria;

--
-- TOC entry 4351 (class 0 OID 0)
-- Dependencies: 234
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.reservacion_habitaciones_detalle_id_seq OWNED BY public.reservacion_habitaciones.detalle_id;


--
-- TOC entry 235 (class 1259 OID 25467)
-- Name: reservacion_servicios; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.reservacion_servicios (
    detalle_servicio_id integer NOT NULL,
    reservacion_id integer,
    servicio_id integer,
    tipo_servicio character varying(50) NOT NULL,
    descripcion character varying(100) NOT NULL,
    fecha_servicio timestamp without time zone NOT NULL,
    cantidad integer DEFAULT 1,
    precio_unitario numeric(10,2) NOT NULL,
    notas text,
    estado character varying(20) DEFAULT 'pendiente'::character varying,
    CONSTRAINT reservacion_servicios_estado_check CHECK (((estado)::text = ANY (ARRAY[('pendiente'::character varying)::text, ('completado'::character varying)::text, ('cancelado'::character varying)::text])))
);


ALTER TABLE public.reservacion_servicios OWNER TO nechavarria;

--
-- TOC entry 236 (class 1259 OID 25475)
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq OWNER TO nechavarria;

--
-- TOC entry 4352 (class 0 OID 0)
-- Dependencies: 236
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq OWNED BY public.reservacion_servicios.detalle_servicio_id;


--
-- TOC entry 237 (class 1259 OID 25476)
-- Name: reservaciones; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.reservaciones (
    reservacion_id integer NOT NULL,
    hotel_id integer,
    cliente_id integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_entrada date NOT NULL,
    fecha_salida date NOT NULL,
    estado character varying(20) NOT NULL,
    tipo_reserva character varying(20) DEFAULT 'individual'::character varying NOT NULL,
    solicitudes_especiales text,
    codigo_reserva character varying(20),
    huespedes integer,
    CONSTRAINT fechas_validas CHECK ((fecha_salida > fecha_entrada)),
    CONSTRAINT reservaciones_estado_check CHECK (((estado)::text = ANY (ARRAY[('pendiente'::character varying)::text, ('confirmada'::character varying)::text, ('cancelada'::character varying)::text, ('completada'::character varying)::text, ('no-show'::character varying)::text]))),
    CONSTRAINT reservaciones_tipo_reserva_check CHECK (((tipo_reserva)::text = ANY (ARRAY[('individual'::character varying)::text, ('grupo'::character varying)::text, ('corporativa'::character varying)::text])))
);


ALTER TABLE public.reservaciones OWNER TO nechavarria;

--
-- TOC entry 238 (class 1259 OID 25487)
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.reservaciones_reservacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservaciones_reservacion_id_seq OWNER TO nechavarria;

--
-- TOC entry 4353 (class 0 OID 0)
-- Dependencies: 238
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.reservaciones_reservacion_id_seq OWNED BY public.reservaciones.reservacion_id;


--
-- TOC entry 239 (class 1259 OID 25488)
-- Name: servicios_hotel; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.servicios_hotel (
    servicio_id integer NOT NULL,
    hotel_id integer,
    nombre character varying(100) NOT NULL,
    descripcion text,
    precio_base numeric(10,2) NOT NULL,
    categoria character varying(50) NOT NULL,
    horario_disponibilidad text,
    activo boolean DEFAULT true
);


ALTER TABLE public.servicios_hotel OWNER TO nechavarria;

--
-- TOC entry 240 (class 1259 OID 25494)
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.servicios_hotel_servicio_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.servicios_hotel_servicio_id_seq OWNER TO nechavarria;

--
-- TOC entry 4354 (class 0 OID 0)
-- Dependencies: 240
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.servicios_hotel_servicio_id_seq OWNED BY public.servicios_hotel.servicio_id;


--
-- TOC entry 241 (class 1259 OID 25495)
-- Name: tarifas_temporada; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.tarifas_temporada (
    tarifa_id integer NOT NULL,
    politica_id integer,
    tipo_id integer,
    precio numeric(10,2) NOT NULL,
    descripcion text
);


ALTER TABLE public.tarifas_temporada OWNER TO nechavarria;

--
-- TOC entry 242 (class 1259 OID 25500)
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.tarifas_temporada_tarifa_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tarifas_temporada_tarifa_id_seq OWNER TO nechavarria;

--
-- TOC entry 4355 (class 0 OID 0)
-- Dependencies: 242
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.tarifas_temporada_tarifa_id_seq OWNED BY public.tarifas_temporada.tarifa_id;


--
-- TOC entry 243 (class 1259 OID 25501)
-- Name: tipos_habitacion; Type: TABLE; Schema: public; Owner: nechavarria
--

CREATE TABLE public.tipos_habitacion (
    tipo_id integer NOT NULL,
    hotel_id integer,
    nombre character varying(50) NOT NULL,
    descripcion text,
    capacidad integer NOT NULL,
    tamano integer,
    comodidades text,
    precio_base numeric(10,2) NOT NULL
);


ALTER TABLE public.tipos_habitacion OWNER TO nechavarria;

--
-- TOC entry 244 (class 1259 OID 25506)
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE; Schema: public; Owner: nechavarria
--

CREATE SEQUENCE public.tipos_habitacion_tipo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipos_habitacion_tipo_id_seq OWNER TO nechavarria;

--
-- TOC entry 4356 (class 0 OID 0)
-- Dependencies: 244
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nechavarria
--

ALTER SEQUENCE public.tipos_habitacion_tipo_id_seq OWNED BY public.tipos_habitacion.tipo_id;


--
-- TOC entry 4034 (class 2604 OID 25671)
-- Name: bitacora_reservaciones bitacora_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.bitacora_reservaciones ALTER COLUMN bitacora_id SET DEFAULT nextval('public.bitacora_reservaciones_bitacora_id_seq'::regclass);


--
-- TOC entry 4005 (class 2604 OID 25507)
-- Name: clientes cliente_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.clientes ALTER COLUMN cliente_id SET DEFAULT nextval('public.clientes_cliente_id_seq'::regclass);


--
-- TOC entry 4008 (class 2604 OID 25508)
-- Name: facturas factura_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.facturas ALTER COLUMN factura_id SET DEFAULT nextval('public.facturas_factura_id_seq'::regclass);


--
-- TOC entry 4009 (class 2604 OID 25509)
-- Name: fidelizacion_clientes fidelizacion_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.fidelizacion_clientes ALTER COLUMN fidelizacion_id SET DEFAULT nextval('public.fidelizacion_clientes_fidelizacion_id_seq'::regclass);


--
-- TOC entry 4012 (class 2604 OID 25510)
-- Name: habitaciones habitacion_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.habitaciones ALTER COLUMN habitacion_id SET DEFAULT nextval('public.habitaciones_habitacion_id_seq'::regclass);


--
-- TOC entry 4017 (class 2604 OID 25511)
-- Name: historico_estadias historico_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.historico_estadias ALTER COLUMN historico_id SET DEFAULT nextval('public.historico_estadias_historico_id_seq'::regclass);


--
-- TOC entry 4018 (class 2604 OID 25512)
-- Name: hoteles hotel_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.hoteles ALTER COLUMN hotel_id SET DEFAULT nextval('public.hoteles_hotel_id_seq'::regclass);


--
-- TOC entry 4020 (class 2604 OID 25513)
-- Name: pagos pago_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.pagos ALTER COLUMN pago_id SET DEFAULT nextval('public.pagos_pago_id_seq'::regclass);


--
-- TOC entry 4022 (class 2604 OID 25514)
-- Name: politicas_temporada politica_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.politicas_temporada ALTER COLUMN politica_id SET DEFAULT nextval('public.politicas_temporada_politica_id_seq'::regclass);


--
-- TOC entry 4023 (class 2604 OID 25515)
-- Name: reservacion_habitaciones detalle_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservacion_habitaciones ALTER COLUMN detalle_id SET DEFAULT nextval('public.reservacion_habitaciones_detalle_id_seq'::regclass);


--
-- TOC entry 4024 (class 2604 OID 25516)
-- Name: reservacion_servicios detalle_servicio_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservacion_servicios ALTER COLUMN detalle_servicio_id SET DEFAULT nextval('public.reservacion_servicios_detalle_servicio_id_seq'::regclass);


--
-- TOC entry 4027 (class 2604 OID 25517)
-- Name: reservaciones reservacion_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservaciones ALTER COLUMN reservacion_id SET DEFAULT nextval('public.reservaciones_reservacion_id_seq'::regclass);


--
-- TOC entry 4030 (class 2604 OID 25518)
-- Name: servicios_hotel servicio_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.servicios_hotel ALTER COLUMN servicio_id SET DEFAULT nextval('public.servicios_hotel_servicio_id_seq'::regclass);


--
-- TOC entry 4032 (class 2604 OID 25519)
-- Name: tarifas_temporada tarifa_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.tarifas_temporada ALTER COLUMN tarifa_id SET DEFAULT nextval('public.tarifas_temporada_tarifa_id_seq'::regclass);


--
-- TOC entry 4033 (class 2604 OID 25520)
-- Name: tipos_habitacion tipo_id; Type: DEFAULT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.tipos_habitacion ALTER COLUMN tipo_id SET DEFAULT nextval('public.tipos_habitacion_tipo_id_seq'::regclass);


--
-- TOC entry 4254 (class 0 OID 25668)
-- Dependencies: 246
-- Data for Name: bitacora_reservaciones; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.bitacora_reservaciones (bitacora_id, usuario, accion, tabla_afectada, id_registro, detalles, direccion_ip, fecha_registro) FROM stdin;
1	nechavarria	CREACION	reservaciones	12	Nueva reserva creada. ID: 12, Estado: confirmada, Fechas: 2024-11-15 al 2025-11-20	186.151.104.75/32	2025-06-12 10:24:52.650148
5	nechavarria	CREACION	reservaciones	17	Nueva reserva creada. ID: 17, Estado: pendiente, Fechas: 2025-07-10 al 2025-07-12	186.151.108.157/32	2025-06-23 18:40:14.341023
\.


--
-- TOC entry 4225 (class 0 OID 25402)
-- Dependencies: 217
-- Data for Name: clientes; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.clientes (cliente_id, nombre, documento_identidad, tipo_documento, nacionalidad, telefono, email, fecha_registro, activo, preferencias, alergias, password_hash) FROM stdin;
999822882	Miguel Torres	00112233	DNI	Per£	+51955556666	miguel.torres@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n ejecutiva	Ninguna	hashed606
2	Juan P‚rez	12345678	DNI	Per£	+51987654321	juan.perez@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con vista al mar	Ninguna	hashed123
4	Carlos L¢pez	11223344	Pasaporte	M‚xico	+525512345678	carlos.lopez@email.com	2025-06-10 02:28:24.361501	t	Suite ejecutiva	Mariscos	hashed789
5	Ana Rodr¡guez	44332211	C‚dula	Colombia	+573012345678	ana.rodriguez@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n cerca del ascensor	L cteos	hashed101
6	Luis Mart¡nez	55667788	DNI	Argentina	+5491134567890	luis.martinez@email.com	2025-06-10 02:28:24.361501	t	Piso alto	Nueces	hashed202
7	Sof¡a Fern ndez	99887766	Pasaporte	Chile	+56987654321	sofia.fernandez@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con terraza	Polen	hashed303
9	Laura Jim‚nez	77889900	C‚dula	Venezuela	+584141234567	laura.jimenez@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n familiar	Chocolate	hashed505
11	Elena Vargas	44556677	Pasaporte	Ecuador	+593987654321	elena.vargas@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con jacuzzi	Penicilina	hashed707
12	Jorge Castro	88990011	DNI	Bolivia	+59171234567	jorge.castro@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n econ¢mica	Huevos	hashed808
13	Patricia Ruiz	22334455	C‚dula	Paraguay	+595981234567	patricia.ruiz@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n doble	Ninguna	hashed909
14	Ricardo Mora	66778899	DNI	Uruguay	+59891234567	ricardo.mora@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con escritorio	Moho	hashed1010
15	Isabel D¡az	1122334455	Pasaporte	Panam 	+50761234567	isabel.diaz@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con balc¢n	Ninguna	hashed1111
16	Fernando Silva	5544332211	DNI	Costa Rica	+50671234567	fernando.silva@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n conectada	L tex	hashed1212
17	Gabriela R¡os	9988776655	C‚dula	Guatemala	+50251234567	gabriela.rios@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con cocina	Ninguna	hashed1313
18	Oscar Mendoza	3344556677	DNI	Rep£blica Dominicana	+18091234567	oscar.mendoza@email.com	2025-06-10 02:28:24.361501	t	Suite presidencial	Mascotas	hashed1414
19	Claudia Herrera	7788990011	Pasaporte	Honduras	+50491234567	claudia.herrera@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con chimenea	Ninguna	hashed1515
20	Daniel Pe¤a	0011223344	DNI	El Salvador	+50371234567	daniel.pena@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n con sala	Cacahuetes	hashed1616
21	Luc¡a Cordero	5566778899	C‚dula	Nicaragua	+50581234567	lucia.cordero@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n tem tica	Ninguna	hashed1717
22	Martin	292929292	DNI	Costa Rica	88888888	juan@example.com	2025-06-10 04:00:07.025529	t	\N	\N	\N
23	Martin	3939393	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 05:46:47.310179	t	\N	\N	\N
10	Mar¡a Gonz lez	87654321	DNI	Per£	+51912345678	maria.gonzalez@email.com	2025-06-10 02:28:24.361501	t	Habitaci¢n silenciosa	Polvo	hashed456
34	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:07.194292	t	\N	\N	\N
35	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:07.209924	t	\N	\N	\N
36	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:07.335345	t	\N	\N	\N
49	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:13.698855	t	\N	\N	\N
37	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:07.350968	t	\N	\N	\N
50	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:13.721024	t	\N	\N	\N
52	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.129893	t	\N	\N	\N
26	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
38	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.020647	t	\N	\N	\N
53	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.265863	t	\N	\N	\N
27	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
39	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.020647	t	\N	\N	\N
55	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.407329	t	\N	\N	\N
28	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
40	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.051895	t	\N	\N	\N
57	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.877971	t	\N	\N	\N
29	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.371668	t	\N	\N	\N
41	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.11481	t	\N	\N	\N
30	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
31	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
46	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:12.440228	t	\N	\N	\N
32	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
33	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:06.372665	t	\N	\N	\N
42	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.208638	t	\N	\N	\N
58	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.830673	t	\N	\N	\N
43	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.255511	t	\N	\N	\N
44	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.255511	t	\N	\N	\N
59	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.98927	t	\N	\N	\N
60	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:15.474231	t	\N	\N	\N
61	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:15.55235	t	\N	\N	\N
62	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:15.819887	t	\N	\N	\N
45	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:08.323345	t	\N	\N	\N
63	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:16.594722	t	\N	\N	\N
64	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:16.813062	t	\N	\N	\N
65	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:16.719311	t	\N	\N	\N
47	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:12.958491	t	\N	\N	\N
67	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:17.563499	t	\N	\N	\N
68	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:18.342169	t	\N	\N	\N
70	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:19.35682	t	\N	\N	\N
48	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:13.06829	t	\N	\N	\N
56	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.288001	t	\N	\N	\N
73	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:19.789124	t	\N	\N	\N
82	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.383686	t	\N	\N	\N
87	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.993383	t	\N	\N	\N
91	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:23.68086	t	\N	\N	\N
1229	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:25.108894	t	\N	\N	\N
1232	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:25.562003	t	\N	\N	\N
1273	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:39.976995	t	\N	\N	\N
1277	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:41.164862	t	\N	\N	\N
1281	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.227619	t	\N	\N	\N
1283	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.430743	t	\N	\N	\N
1293	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:45.603472	t	\N	\N	\N
1303	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:48.510663	t	\N	\N	\N
1305	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:48.77628	t	\N	\N	\N
1325	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:56.029354	t	\N	\N	\N
1342	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:00.889731	t	\N	\N	\N
1357	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.173331	t	\N	\N	\N
1362	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.704659	t	\N	\N	\N
1378	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:12.955429	t	\N	\N	\N
1385	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:15.62799	t	\N	\N	\N
1387	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:16.458081	t	\N	\N	\N
1230	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:25.233897	t	\N	\N	\N
80	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.6802	t	\N	\N	\N
90	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:23.274622	t	\N	\N	\N
92	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:23.743358	t	\N	\N	\N
1237	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:26.969258	t	\N	\N	\N
1247	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:31.723044	t	\N	\N	\N
1271	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:39.242191	t	\N	\N	\N
1286	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.883967	t	\N	\N	\N
1290	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:44.837055	t	\N	\N	\N
51	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.066979	t	\N	\N	\N
1344	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:02.265195	t	\N	\N	\N
1349	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:04.626278	t	\N	\N	\N
1352	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:06.673226	t	\N	\N	\N
54	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:14.265863	t	\N	\N	\N
1355	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.017091	t	\N	\N	\N
1359	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.313955	t	\N	\N	\N
1369	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:09.673502	t	\N	\N	\N
1371	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:10.579956	t	\N	\N	\N
1373	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:10.767446	t	\N	\N	\N
1377	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:12.89293	t	\N	\N	\N
1382	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:14.971759	t	\N	\N	\N
66	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:17.501005	t	\N	\N	\N
69	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:19.04557	t	\N	\N	\N
72	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:19.742252	t	\N	\N	\N
71	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:19.530597	t	\N	\N	\N
74	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:20.695342	t	\N	\N	\N
86	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.899637	t	\N	\N	\N
93	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:24.368334	t	\N	\N	\N
96	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:24.962639	t	\N	\N	\N
1231	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:25.546385	t	\N	\N	\N
1238	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:27.10987	t	\N	\N	\N
1245	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:31.378913	t	\N	\N	\N
1255	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:34.271271	t	\N	\N	\N
1259	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:36.037711	t	\N	\N	\N
1270	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:38.944819	t	\N	\N	\N
1289	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:44.805806	t	\N	\N	\N
1307	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:49.245268	t	\N	\N	\N
1309	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:49.651512	t	\N	\N	\N
1311	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:50.823875	t	\N	\N	\N
1321	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:55.012809	t	\N	\N	\N
1332	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:58.31106	t	\N	\N	\N
1336	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:59.483343	t	\N	\N	\N
1356	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.095206	t	\N	\N	\N
1360	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.595291	t	\N	\N	\N
1366	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:08.891731	t	\N	\N	\N
1374	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:10.829947	t	\N	\N	\N
1	Marlon Actualizado	922148201	DNI	Costa Rica	71235293	martinactualizado@example.com	2025-06-29 07:38:16.73408	t	\N	\N	\N
1233	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:25.702622	t	\N	\N	\N
1249	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:32.552478	t	\N	\N	\N
1297	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:47.244839	t	\N	\N	\N
1301	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:47.97943	t	\N	\N	\N
1320	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:54.731574	t	\N	\N	\N
76	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.258339	t	\N	\N	\N
1329	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:57.451313	t	\N	\N	\N
1331	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:58.029412	t	\N	\N	\N
1337	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:59.59271	t	\N	\N	\N
1338	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:59.827072	t	\N	\N	\N
1340	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:00.139761	t	\N	\N	\N
1343	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:01.577661	t	\N	\N	\N
1347	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:04.047381	t	\N	\N	\N
1365	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.876527	t	\N	\N	\N
84	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.868387	t	\N	\N	\N
1386	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:15.815481	t	\N	\N	\N
97	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:25.884728	t	\N	\N	\N
75	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:20.804716	t	\N	\N	\N
77	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.211467	t	\N	\N	\N
81	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.72707	t	\N	\N	\N
1234	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:26.124963	t	\N	\N	\N
1235	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:26.515572	t	\N	\N	\N
1236	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:26.62538	t	\N	\N	\N
1239	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:27.17281	t	\N	\N	\N
1256	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:35.068124	t	\N	\N	\N
1287	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:44.602687	t	\N	\N	\N
1295	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:46.635404	t	\N	\N	\N
1300	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:47.791681	t	\N	\N	\N
1308	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:49.276526	t	\N	\N	\N
1326	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:56.076251	t	\N	\N	\N
1328	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:57.35746	t	\N	\N	\N
1353	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:06.735722	t	\N	\N	\N
1363	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.751531	t	\N	\N	\N
1368	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:09.297974	t	\N	\N	\N
1384	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:15.471752	t	\N	\N	\N
1396	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:20.629691	t	\N	\N	\N
78	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.586456	t	\N	\N	\N
88	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.91526	t	\N	\N	\N
95	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:24.962639	t	\N	\N	\N
1240	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:28.001249	t	\N	\N	\N
1243	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:30.878486	t	\N	\N	\N
1244	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:31.237849	t	\N	\N	\N
1253	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:33.974255	t	\N	\N	\N
1263	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.085066	t	\N	\N	\N
1265	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.381942	t	\N	\N	\N
1285	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.711982	t	\N	\N	\N
1298	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:47.71356	t	\N	\N	\N
1302	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:48.37004	t	\N	\N	\N
1306	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:48.8544	t	\N	\N	\N
1323	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:55.106991	t	\N	\N	\N
1324	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:55.560179	t	\N	\N	\N
1335	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:59.327086	t	\N	\N	\N
1350	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:05.595075	t	\N	\N	\N
1361	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.642163	t	\N	\N	\N
1383	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:15.190505	t	\N	\N	\N
1393	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:17.941318	t	\N	\N	\N
79	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:21.633325	t	\N	\N	\N
83	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.680549	t	\N	\N	\N
1241	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:28.736326	t	\N	\N	\N
1248	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:32.192199	t	\N	\N	\N
1250	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:32.708675	t	\N	\N	\N
1251	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:33.114916	t	\N	\N	\N
1257	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:35.239988	t	\N	\N	\N
1262	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.085066	t	\N	\N	\N
1264	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.194434	t	\N	\N	\N
1266	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.866302	t	\N	\N	\N
1272	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:39.601552	t	\N	\N	\N
1279	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:41.758914	t	\N	\N	\N
1280	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:42.227649	t	\N	\N	\N
1310	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:50.761378	t	\N	\N	\N
1314	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:52.621176	t	\N	\N	\N
1316	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:53.136885	t	\N	\N	\N
1339	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:00.045812	t	\N	\N	\N
1351	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:05.688825	t	\N	\N	\N
1394	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:18.300687	t	\N	\N	\N
1395	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:19.957683	t	\N	\N	\N
1398	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:22.192897	t	\N	\N	\N
1400	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:23.56808	t	\N	\N	\N
85	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:22.727423	t	\N	\N	\N
89	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:23.227748	t	\N	\N	\N
1242	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:29.549602	t	\N	\N	\N
1254	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:34.16198	t	\N	\N	\N
1258	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:35.896585	t	\N	\N	\N
1268	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:38.507318	t	\N	\N	\N
1330	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:57.732549	t	\N	\N	\N
1276	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:41.11799	t	\N	\N	\N
1354	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:06.766971	t	\N	\N	\N
1278	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:41.649223	t	\N	\N	\N
1367	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:08.985484	t	\N	\N	\N
1315	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:52.949393	t	\N	\N	\N
1375	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:11.267811	t	\N	\N	\N
1376	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:11.627177	t	\N	\N	\N
1292	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:45.055808	t	\N	\N	\N
1319	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:54.371943	t	\N	\N	\N
1346	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:03.65669	t	\N	\N	\N
1380	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:12.87731	t	\N	\N	\N
1348	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:04.094259	t	\N	\N	\N
1304	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:48.77628	t	\N	\N	\N
94	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:24.821735	t	\N	\N	\N
98	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:26.635263	t	\N	\N	\N
99	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:26.697764	t	\N	\N	\N
100	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:27.08837	t	\N	\N	\N
101	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:27.229001	t	\N	\N	\N
102	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:27.604411	t	\N	\N	\N
103	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:27.838782	t	\N	\N	\N
104	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:28.386256	t	\N	\N	\N
105	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:28.605006	t	\N	\N	\N
128	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:34.375664	t	\N	\N	\N
129	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:34.547532	t	\N	\N	\N
106	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:28.917497	t	\N	\N	\N
131	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:35.146393	t	\N	\N	\N
132	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:35.969876	t	\N	\N	\N
107	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:28.979993	t	\N	\N	\N
108	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.058108	t	\N	\N	\N
109	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.058108	t	\N	\N	\N
134	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:36.548301	t	\N	\N	\N
110	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.183145	t	\N	\N	\N
136	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:36.688902	t	\N	\N	\N
138	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:36.829529	t	\N	\N	\N
111	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.30814	t	\N	\N	\N
139	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:37.267014	t	\N	\N	\N
112	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.620626	t	\N	\N	\N
113	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.651878	t	\N	\N	\N
114	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.667499	t	\N	\N	\N
140	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:37.504128	t	\N	\N	\N
141	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:37.504128	t	\N	\N	\N
142	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:37.877647	t	\N	\N	\N
115	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:29.96437	t	\N	\N	\N
116	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:30.402573	t	\N	\N	\N
144	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:38.518059	t	\N	\N	\N
145	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:38.549318	t	\N	\N	\N
146	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:39.080273	t	\N	\N	\N
117	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:30.746439	t	\N	\N	\N
148	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:39.377138	t	\N	\N	\N
149	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:40.471412	t	\N	\N	\N
118	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:31.043589	t	\N	\N	\N
151	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:40.924524	t	\N	\N	\N
119	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:31.059225	t	\N	\N	\N
152	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:41.158892	t	\N	\N	\N
155	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:42.08091	t	\N	\N	\N
156	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:42.643783	t	\N	\N	\N
157	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.050219	t	\N	\N	\N
120	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:31.810449	t	\N	\N	\N
121	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:31.810449	t	\N	\N	\N
158	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.300244	t	\N	\N	\N
122	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:31.951068	t	\N	\N	\N
168	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.16122	t	\N	\N	\N
170	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.865115	t	\N	\N	\N
123	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:32.654069	t	\N	\N	\N
171	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.88074	t	\N	\N	\N
124	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:32.749033	t	\N	\N	\N
160	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.50338	t	\N	\N	\N
172	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.943241	t	\N	\N	\N
173	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.958864	t	\N	\N	\N
125	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:33.170896	t	\N	\N	\N
174	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:48.380723	t	\N	\N	\N
177	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:49.381262	t	\N	\N	\N
164	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:44.989125	t	\N	\N	\N
179	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:49.912309	t	\N	\N	\N
161	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.67525	t	\N	\N	\N
181	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:50.851201	t	\N	\N	\N
183	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:51.429306	t	\N	\N	\N
184	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:52.398125	t	\N	\N	\N
188	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:53.320564	t	\N	\N	\N
166	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:45.645513	t	\N	\N	\N
190	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:53.61761	t	\N	\N	\N
192	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:54.18051	t	\N	\N	\N
194	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:54.727949	t	\N	\N	\N
1246	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:31.332033	t	\N	\N	\N
165	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:45.563819	t	\N	\N	\N
178	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:49.646868	t	\N	\N	\N
191	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:53.805102	t	\N	\N	\N
198	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:55.493868	t	\N	\N	\N
200	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:55.86886	t	\N	\N	\N
203	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.40009	t	\N	\N	\N
207	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.806325	t	\N	\N	\N
213	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:58.711282	t	\N	\N	\N
217	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:00.719928	t	\N	\N	\N
228	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:03.621977	t	\N	\N	\N
244	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:07.541287	t	\N	\N	\N
261	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.711585	t	\N	\N	\N
286	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:18.492819	t	\N	\N	\N
290	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:21.175035	t	\N	\N	\N
298	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.446332	t	\N	\N	\N
1260	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:36.209488	t	\N	\N	\N
1261	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:36.756659	t	\N	\N	\N
1274	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:40.570851	t	\N	\N	\N
1291	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:44.883934	t	\N	\N	\N
1299	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:47.744806	t	\N	\N	\N
1317	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:53.340307	t	\N	\N	\N
1318	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:54.028206	t	\N	\N	\N
1358	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.267076	t	\N	\N	\N
1364	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:07.751531	t	\N	\N	\N
1370	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:10.517456	t	\N	\N	\N
1372	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:10.595582	t	\N	\N	\N
1381	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:13.861956	t	\N	\N	\N
1389	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:16.800114	t	\N	\N	\N
1391	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:17.831949	t	\N	\N	\N
1397	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:20.629691	t	\N	\N	\N
126	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:33.921717	t	\N	\N	\N
130	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:34.68816	t	\N	\N	\N
135	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:36.657655	t	\N	\N	\N
150	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:40.596409	t	\N	\N	\N
153	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:41.455759	t	\N	\N	\N
163	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.940914	t	\N	\N	\N
193	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:54.305508	t	\N	\N	\N
215	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:59.771105	t	\N	\N	\N
216	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:00.591921	t	\N	\N	\N
230	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:03.828049	t	\N	\N	\N
237	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:05.045057	t	\N	\N	\N
267	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.581676	t	\N	\N	\N
271	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:13.605118	t	\N	\N	\N
283	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:17.990849	t	\N	\N	\N
287	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:19.088987	t	\N	\N	\N
299	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.509241	t	\N	\N	\N
301	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:23.32576	t	\N	\N	\N
303	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:24.62833	t	\N	\N	\N
1252	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:33.114916	t	\N	\N	\N
1267	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:37.991296	t	\N	\N	\N
1269	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:38.929183	t	\N	\N	\N
1275	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:41.071114	t	\N	\N	\N
1282	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.25887	t	\N	\N	\N
1284	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:43.430743	t	\N	\N	\N
1288	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:44.774559	t	\N	\N	\N
1294	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:46.338263	t	\N	\N	\N
1296	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:46.822956	t	\N	\N	\N
1312	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:51.605106	t	\N	\N	\N
1313	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:52.07422	t	\N	\N	\N
1322	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:55.060116	t	\N	\N	\N
1327	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:56.263746	t	\N	\N	\N
1333	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:58.389184	t	\N	\N	\N
1334	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:58.952107	t	\N	\N	\N
1341	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:00.217874	t	\N	\N	\N
1345	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:03.00039	t	\N	\N	\N
1379	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:13.002307	t	\N	\N	\N
1388	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:16.67512	t	\N	\N	\N
127	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:34.172545	t	\N	\N	\N
133	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:35.985497	t	\N	\N	\N
137	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:36.67328	t	\N	\N	\N
143	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:38.221387	t	\N	\N	\N
147	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:39.142781	t	\N	\N	\N
154	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:42.034037	t	\N	\N	\N
159	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.409639	t	\N	\N	\N
162	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:43.800282	t	\N	\N	\N
176	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:49.225001	t	\N	\N	\N
182	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:51.069943	t	\N	\N	\N
186	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:52.836019	t	\N	\N	\N
189	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:53.367439	t	\N	\N	\N
201	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.228218	t	\N	\N	\N
221	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:01.344928	t	\N	\N	\N
233	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:04.062413	t	\N	\N	\N
236	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:04.998191	t	\N	\N	\N
242	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:06.806616	t	\N	\N	\N
248	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:08.790356	t	\N	\N	\N
253	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.602627	t	\N	\N	\N
277	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:15.80322	t	\N	\N	\N
289	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:20.688601	t	\N	\N	\N
300	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:23.137414	t	\N	\N	\N
302	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:23.812226	t	\N	\N	\N
305	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:24.89517	t	\N	\N	\N
1390	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:16.90977	t	\N	\N	\N
1392	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:17.910068	t	\N	\N	\N
1399	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:22.364766	t	\N	\N	\N
169	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:47.317487	t	\N	\N	\N
175	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:48.959389	t	\N	\N	\N
180	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:50.115851	t	\N	\N	\N
167	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:45.73926	t	\N	\N	\N
185	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:52.585619	t	\N	\N	\N
187	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:53.101653	t	\N	\N	\N
209	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.994294	t	\N	\N	\N
224	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:02.132655	t	\N	\N	\N
243	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:07.291291	t	\N	\N	\N
249	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.102843	t	\N	\N	\N
255	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.711793	t	\N	\N	\N
288	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:19.371154	t	\N	\N	\N
1401	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:24.021191	t	\N	\N	\N
1405	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:25.193506	t	\N	\N	\N
1412	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:27.490839	t	\N	\N	\N
1415	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:28.647374	t	\N	\N	\N
1422	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:31.539022	t	\N	\N	\N
1423	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:31.992511	t	\N	\N	\N
1427	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:34.024006	t	\N	\N	\N
1435	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:37.839048	t	\N	\N	\N
1436	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:38.136255	t	\N	\N	\N
1447	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:43.331899	t	\N	\N	\N
1475	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:56.332417	t	\N	\N	\N
1500	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:06.396669	t	\N	\N	\N
1506	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:09.217611	t	\N	\N	\N
1516	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:12.434104	t	\N	\N	\N
1402	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:24.083698	t	\N	\N	\N
240	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:06.572247	t	\N	\N	\N
246	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:08.508385	t	\N	\N	\N
251	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.540132	t	\N	\N	\N
257	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:10.868411	t	\N	\N	\N
263	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.87992	t	\N	\N	\N
266	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.292918	t	\N	\N	\N
270	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.992716	t	\N	\N	\N
275	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:15.197236	t	\N	\N	\N
276	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:15.709057	t	\N	\N	\N
281	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:17.29402	t	\N	\N	\N
291	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:21.269183	t	\N	\N	\N
293	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.006951	t	\N	\N	\N
296	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.336544	t	\N	\N	\N
1414	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:27.959901	t	\N	\N	\N
1420	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:30.476264	t	\N	\N	\N
1450	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:44.074389	t	\N	\N	\N
1456	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:47.137447	t	\N	\N	\N
1457	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:47.292876	t	\N	\N	\N
1464	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:52.848324	t	\N	\N	\N
1476	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:56.677991	t	\N	\N	\N
1491	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:02.723426	t	\N	\N	\N
1507	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:09.217611	t	\N	\N	\N
210	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:57.072415	t	\N	\N	\N
214	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:59.126258	t	\N	\N	\N
195	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:54.868571	t	\N	\N	\N
196	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:55.368872	t	\N	\N	\N
202	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.384464	t	\N	\N	\N
205	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.587582	t	\N	\N	\N
208	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.916157	t	\N	\N	\N
1403	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:24.318231	t	\N	\N	\N
1408	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:28.975491	t	\N	\N	\N
1411	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:27.287536	t	\N	\N	\N
1416	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:29.444224	t	\N	\N	\N
1434	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:37.526108	t	\N	\N	\N
1438	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:38.683251	t	\N	\N	\N
1441	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:40.578783	t	\N	\N	\N
1445	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:41.614652	t	\N	\N	\N
1458	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:47.528013	t	\N	\N	\N
1478	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:56.819441	t	\N	\N	\N
1485	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:00.347669	t	\N	\N	\N
1494	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:04.020738	t	\N	\N	\N
1497	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:05.052299	t	\N	\N	\N
1511	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:11.07978	t	\N	\N	\N
197	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:55.43137	t	\N	\N	\N
219	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:00.958938	t	\N	\N	\N
220	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:01.335923	t	\N	\N	\N
238	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:05.295484	t	\N	\N	\N
241	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:06.619118	t	\N	\N	\N
265	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.107705	t	\N	\N	\N
269	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.657073	t	\N	\N	\N
294	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.085515	t	\N	\N	\N
1404	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:24.615101	t	\N	\N	\N
1430	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:35.75962	t	\N	\N	\N
1442	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:40.61003	t	\N	\N	\N
1463	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:52.704727	t	\N	\N	\N
1474	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:55.846243	t	\N	\N	\N
1480	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:57.164534	t	\N	\N	\N
1483	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:58.518021	t	\N	\N	\N
1496	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:04.755452	t	\N	\N	\N
1501	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:06.677903	t	\N	\N	\N
1503	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:08.084964	t	\N	\N	\N
1512	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:11.227075	t	\N	\N	\N
1518	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:12.699722	t	\N	\N	\N
199	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:55.681362	t	\N	\N	\N
204	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.540708	t	\N	\N	\N
211	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:57.103685	t	\N	\N	\N
212	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:58.369802	t	\N	\N	\N
225	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:02.233639	t	\N	\N	\N
231	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:03.999921	t	\N	\N	\N
235	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:04.576325	t	\N	\N	\N
258	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.009021	t	\N	\N	\N
282	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:17.827355	t	\N	\N	\N
284	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:19.754432	t	\N	\N	\N
304	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:24.816637	t	\N	\N	\N
1406	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:25.459125	t	\N	\N	\N
1407	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:25.630988	t	\N	\N	\N
1417	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:29.522344	t	\N	\N	\N
1439	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:38.901995	t	\N	\N	\N
1446	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:43.004509	t	\N	\N	\N
1454	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:46.319896	t	\N	\N	\N
1459	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:48.438538	t	\N	\N	\N
1481	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:57.556852	t	\N	\N	\N
1486	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:01.16048	t	\N	\N	\N
1489	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:01.941703	t	\N	\N	\N
1495	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:04.208551	t	\N	\N	\N
1504	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:08.906969	t	\N	\N	\N
206	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:30:56.743834	t	\N	\N	\N
222	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:01.400924	t	\N	\N	\N
223	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:01.817911	t	\N	\N	\N
226	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:02.371645	t	\N	\N	\N
227	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:02.73862	t	\N	\N	\N
229	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:03.781172	t	\N	\N	\N
232	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:03.906168	t	\N	\N	\N
234	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:04.093669	t	\N	\N	\N
247	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:08.712227	t	\N	\N	\N
252	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.555759	t	\N	\N	\N
264	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.09208	t	\N	\N	\N
268	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:12.742721	t	\N	\N	\N
272	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:14.048487	t	\N	\N	\N
278	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:15.91342	t	\N	\N	\N
279	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:16.902492	t	\N	\N	\N
285	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:18.414254	t	\N	\N	\N
292	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:21.395084	t	\N	\N	\N
1409	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:25.865356	t	\N	\N	\N
1418	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:30.09316	t	\N	\N	\N
1429	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:35.587758	t	\N	\N	\N
1433	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:36.681605	t	\N	\N	\N
1440	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:39.825319	t	\N	\N	\N
1451	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:44.969597	t	\N	\N	\N
1461	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:50.71397	t	\N	\N	\N
1467	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:53.382173	t	\N	\N	\N
1493	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:03.598473	t	\N	\N	\N
1510	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:10.852309	t	\N	\N	\N
218	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:00.923936	t	\N	\N	\N
239	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:05.561599	t	\N	\N	\N
245	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:07.98982	t	\N	\N	\N
254	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.711793	t	\N	\N	\N
260	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.321879	t	\N	\N	\N
262	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.749693	t	\N	\N	\N
273	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:14.760283	t	\N	\N	\N
295	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.195499	t	\N	\N	\N
297	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:22.415084	t	\N	\N	\N
1410	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:27.287536	t	\N	\N	\N
1413	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:27.600522	t	\N	\N	\N
1421	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:30.913742	t	\N	\N	\N
1425	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:33.11779	t	\N	\N	\N
1426	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:33.83651	t	\N	\N	\N
1432	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:36.353485	t	\N	\N	\N
1444	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:41.56778	t	\N	\N	\N
1460	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:48.815271	t	\N	\N	\N
1466	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:53.287982	t	\N	\N	\N
1471	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:54.590492	t	\N	\N	\N
1473	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:55.390865	t	\N	\N	\N
1477	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:56.693619	t	\N	\N	\N
1482	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:58.452006	t	\N	\N	\N
1484	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:59.534431	t	\N	\N	\N
1488	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:01.691715	t	\N	\N	\N
1509	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:09.699475	t	\N	\N	\N
315	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.760448	t	\N	\N	\N
316	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.885448	t	\N	\N	\N
317	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:28.026064	t	\N	\N	\N
318	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:28.244815	t	\N	\N	\N
250	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:09.11847	t	\N	\N	\N
280	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:17.09031	t	\N	\N	\N
319	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:28.338987	t	\N	\N	\N
330	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:32.914326	t	\N	\N	\N
332	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:33.253315	t	\N	\N	\N
334	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.121367	t	\N	\N	\N
335	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.173372	t	\N	\N	\N
256	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:10.712157	t	\N	\N	\N
336	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.350796	t	\N	\N	\N
337	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.406791	t	\N	\N	\N
338	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.441793	t	\N	\N	\N
320	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:29.323397	t	\N	\N	\N
339	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.667783	t	\N	\N	\N
259	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:11.118764	t	\N	\N	\N
341	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:35.728164	t	\N	\N	\N
342	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:36.61753	t	\N	\N	\N
343	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:36.80573	t	\N	\N	\N
344	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:37.600702	t	\N	\N	\N
346	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:37.824022	t	\N	\N	\N
349	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:39.508578	t	\N	\N	\N
350	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:39.637579	t	\N	\N	\N
351	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:39.810561	t	\N	\N	\N
353	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:40.492541	t	\N	\N	\N
321	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:30.368441	t	\N	\N	\N
355	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:40.61854	t	\N	\N	\N
322	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:30.392441	t	\N	\N	\N
306	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:25.115175	t	\N	\N	\N
358	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:42.720467	t	\N	\N	\N
359	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.072452	t	\N	\N	\N
307	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:25.665627	t	\N	\N	\N
360	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.419445	t	\N	\N	\N
361	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.430443	t	\N	\N	\N
323	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:30.697221	t	\N	\N	\N
362	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.524438	t	\N	\N	\N
308	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:26.243626	t	\N	\N	\N
309	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:26.509245	t	\N	\N	\N
363	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.588439	t	\N	\N	\N
274	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:14.877288	t	\N	\N	\N
365	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:43.607439	t	\N	\N	\N
310	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:26.696737	t	\N	\N	\N
324	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:30.967218	t	\N	\N	\N
325	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:31.025207	t	\N	\N	\N
366	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:44.670566	t	\N	\N	\N
311	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.181455	t	\N	\N	\N
312	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.181455	t	\N	\N	\N
367	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:45.012553	t	\N	\N	\N
313	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.369361	t	\N	\N	\N
314	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:27.384982	t	\N	\N	\N
370	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:51.053876	t	\N	\N	\N
371	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:51.428826	t	\N	\N	\N
372	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.022553	t	\N	\N	\N
326	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:31.63519	t	\N	\N	\N
374	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.147547	t	\N	\N	\N
375	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.241294	t	\N	\N	\N
377	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.694403	t	\N	\N	\N
379	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:53.225812	t	\N	\N	\N
327	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:32.200828	t	\N	\N	\N
380	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:53.225812	t	\N	\N	\N
328	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:32.697811	t	\N	\N	\N
381	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:53.303935	t	\N	\N	\N
382	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:53.491427	t	\N	\N	\N
384	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:54.178901	t	\N	\N	\N
385	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:55.038671	t	\N	\N	\N
386	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:55.226161	t	\N	\N	\N
387	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:55.585776	t	\N	\N	\N
389	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:55.960767	t	\N	\N	\N
1419	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:30.148139	t	\N	\N	\N
403	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:59.087385	t	\N	\N	\N
415	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:03.026906	t	\N	\N	\N
416	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:03.245648	t	\N	\N	\N
417	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:03.3394	t	\N	\N	\N
420	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:04.73046	t	\N	\N	\N
428	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.870831	t	\N	\N	\N
441	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:12.702728	t	\N	\N	\N
443	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:13.672783	t	\N	\N	\N
450	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:15.18918	t	\N	\N	\N
481	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.022719	t	\N	\N	\N
1424	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:32.414368	t	\N	\N	\N
1443	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:41.096946	t	\N	\N	\N
1452	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:45.361888	t	\N	\N	\N
1455	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:46.947799	t	\N	\N	\N
1462	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:50.760864	t	\N	\N	\N
1470	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:54.433807	t	\N	\N	\N
340	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:35.375916	t	\N	\N	\N
1472	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:55.218527	t	\N	\N	\N
1487	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:01.597971	t	\N	\N	\N
1490	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:02.113576	t	\N	\N	\N
1515	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:12.215057	t	\N	\N	\N
345	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:37.64969	t	\N	\N	\N
347	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:38.035015	t	\N	\N	\N
373	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.069424	t	\N	\N	\N
378	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.788153	t	\N	\N	\N
383	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:54.397656	t	\N	\N	\N
329	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:32.878328	t	\N	\N	\N
331	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:33.266315	t	\N	\N	\N
333	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:34.109368	t	\N	\N	\N
348	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:38.838219	t	\N	\N	\N
352	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:40.489537	t	\N	\N	\N
354	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:40.520543	t	\N	\N	\N
356	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:40.790527	t	\N	\N	\N
357	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:41.916497	t	\N	\N	\N
364	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:44.168421	t	\N	\N	\N
368	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:45.233549	t	\N	\N	\N
369	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:50.069542	t	\N	\N	\N
376	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:52.522537	t	\N	\N	\N
390	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:56.195128	t	\N	\N	\N
391	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:56.882758	t	\N	\N	\N
397	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.117775	t	\N	\N	\N
399	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.164634	t	\N	\N	\N
407	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:00.228708	t	\N	\N	\N
408	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:00.566137	t	\N	\N	\N
409	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:00.932042	t	\N	\N	\N
418	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:04.011293	t	\N	\N	\N
425	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.136824	t	\N	\N	\N
435	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:10.732185	t	\N	\N	\N
442	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:12.780847	t	\N	\N	\N
444	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:13.797774	t	\N	\N	\N
458	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:17.299971	t	\N	\N	\N
463	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:18.910579	t	\N	\N	\N
477	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:23.13248	t	\N	\N	\N
482	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.116466	t	\N	\N	\N
484	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.553962	t	\N	\N	\N
487	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.944865	t	\N	\N	\N
488	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.976114	t	\N	\N	\N
1428	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:34.602402	t	\N	\N	\N
1448	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:43.666428	t	\N	\N	\N
1465	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:53.005522	t	\N	\N	\N
1469	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:54.339636	t	\N	\N	\N
1498	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:05.34916	t	\N	\N	\N
1499	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:05.990336	t	\N	\N	\N
1502	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:07.131781	t	\N	\N	\N
1505	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:09.186368	t	\N	\N	\N
1508	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:09.577793	t	\N	\N	\N
1513	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:11.433829	t	\N	\N	\N
1519	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:16.021096	t	\N	\N	\N
1431	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:36.087729	t	\N	\N	\N
430	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:09.043545	t	\N	\N	\N
433	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:09.825076	t	\N	\N	\N
434	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:10.607188	t	\N	\N	\N
440	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:12.671483	t	\N	\N	\N
1437	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:38.230004	t	\N	\N	\N
1449	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:43.98572	t	\N	\N	\N
1453	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:45.613214	t	\N	\N	\N
1468	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:53.743279	t	\N	\N	\N
1479	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:37:56.881959	t	\N	\N	\N
1492	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:03.473395	t	\N	\N	\N
1514	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:12.159732	t	\N	\N	\N
1517	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:38:12.496601	t	\N	\N	\N
396	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.086514	t	\N	\N	\N
466	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:19.708195	t	\N	\N	\N
405	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:59.149883	t	\N	\N	\N
388	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:55.585776	t	\N	\N	\N
393	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:57.289663	t	\N	\N	\N
398	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.133382	t	\N	\N	\N
400	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.320881	t	\N	\N	\N
401	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.978013	t	\N	\N	\N
413	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:01.853896	t	\N	\N	\N
423	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:06.104956	t	\N	\N	\N
429	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.902073	t	\N	\N	\N
474	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:21.991593	t	\N	\N	\N
8	Pedro S nchez	33445566	DNI	Espana	+34678901234	pedro.sanchez@email.com	2025-06-29 14:58:08.353383	t	Habitaci¢n adaptada	Gluten	hashed_password_123
447	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:14.704522	t	\N	\N	\N
392	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:56.914473	t	\N	\N	\N
406	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:59.681108	t	\N	\N	\N
411	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:01.619525	t	\N	\N	\N
424	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.058676	t	\N	\N	\N
432	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:09.371659	t	\N	\N	\N
437	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:11.075923	t	\N	\N	\N
462	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:18.738916	t	\N	\N	\N
464	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:19.144954	t	\N	\N	\N
475	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:22.882594	t	\N	\N	\N
480	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:23.600868	t	\N	\N	\N
486	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:25.852105	t	\N	\N	\N
394	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:57.992767	t	\N	\N	\N
402	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:59.05613	t	\N	\N	\N
410	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:01.119539	t	\N	\N	\N
414	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:02.651924	t	\N	\N	\N
445	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:14.063514	t	\N	\N	\N
446	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:14.579524	t	\N	\N	\N
453	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:16.126962	t	\N	\N	\N
455	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:16.674107	t	\N	\N	\N
459	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:17.549974	t	\N	\N	\N
465	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:19.630079	t	\N	\N	\N
467	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:20.255718	t	\N	\N	\N
479	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:23.569607	t	\N	\N	\N
422	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:05.83933	t	\N	\N	\N
431	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:09.106038	t	\N	\N	\N
395	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:58.03964	t	\N	\N	\N
404	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:31:59.118629	t	\N	\N	\N
412	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:01.744513	t	\N	\N	\N
419	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:04.683578	t	\N	\N	\N
421	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:05.714322	t	\N	\N	\N
427	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.214957	t	\N	\N	\N
448	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:14.923566	t	\N	\N	\N
451	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:15.407918	t	\N	\N	\N
452	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:15.923535	t	\N	\N	\N
456	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:16.924083	t	\N	\N	\N
460	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:17.831904	t	\N	\N	\N
461	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:18.238132	t	\N	\N	\N
471	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:21.39735	t	\N	\N	\N
472	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:21.881711	t	\N	\N	\N
426	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:07.136824	t	\N	\N	\N
436	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:11.060292	t	\N	\N	\N
438	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:11.873339	t	\N	\N	\N
457	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:17.111576	t	\N	\N	\N
469	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:20.866006	t	\N	\N	\N
470	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:21.334827	t	\N	\N	\N
473	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:22.069707	t	\N	\N	\N
476	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:23.085709	t	\N	\N	\N
478	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:23.569607	t	\N	\N	\N
439	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:11.951461	t	\N	\N	\N
449	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:14.986069	t	\N	\N	\N
454	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:16.470707	t	\N	\N	\N
468	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:20.787897	t	\N	\N	\N
483	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.24147	t	\N	\N	\N
485	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:24.694579	t	\N	\N	\N
489	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:25.429798	t	\N	\N	\N
490	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:25.523548	t	\N	\N	\N
491	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:25.898978	t	\N	\N	\N
492	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:26.352493	t	\N	\N	\N
493	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:26.868102	t	\N	\N	\N
494	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:27.321356	t	\N	\N	\N
495	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:27.368218	t	\N	\N	\N
496	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:27.962647	t	\N	\N	\N
497	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:28.072038	t	\N	\N	\N
498	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:28.759959	t	\N	\N	\N
499	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.182258	t	\N	\N	\N
500	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.35413	t	\N	\N	\N
501	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.51037	t	\N	\N	\N
502	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.713563	t	\N	\N	\N
503	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.776068	t	\N	\N	\N
504	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:29.869813	t	\N	\N	\N
505	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:30.682536	t	\N	\N	\N
506	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:31.08886	t	\N	\N	\N
507	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:31.417021	t	\N	\N	\N
508	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:31.776384	t	\N	\N	\N
509	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:32.010754	t	\N	\N	\N
510	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:32.29245	t	\N	\N	\N
511	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:32.386199	t	\N	\N	\N
512	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:32.573689	t	\N	\N	\N
513	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:32.651814	t	\N	\N	\N
514	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:33.480321	t	\N	\N	\N
515	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:33.699067	t	\N	\N	\N
516	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:33.761555	t	\N	\N	\N
517	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:33.94947	t	\N	\N	\N
518	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:34.05884	t	\N	\N	\N
519	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:34.258331	t	\N	\N	\N
520	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:34.792127	t	\N	\N	\N
521	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:35.070788	t	\N	\N	\N
522	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:35.367659	t	\N	\N	\N
523	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:35.461716	t	\N	\N	\N
524	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:35.508622	t	\N	\N	\N
525	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:35.575628	t	\N	\N	\N
526	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:36.233545	t	\N	\N	\N
527	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:36.635317	t	\N	\N	\N
528	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:36.588445	t	\N	\N	\N
529	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:36.807183	t	\N	\N	\N
530	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:37.073276	t	\N	\N	\N
531	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:37.24706	t	\N	\N	\N
532	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:37.291961	t	\N	\N	\N
533	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:37.79194	t	\N	\N	\N
534	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:37.916946	t	\N	\N	\N
535	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:38.465124	t	\N	\N	\N
536	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:38.746359	t	\N	\N	\N
537	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:39.121341	t	\N	\N	\N
538	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:39.215548	t	\N	\N	\N
550	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:42.919008	t	\N	\N	\N
551	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.16939	t	\N	\N	\N
553	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.278746	t	\N	\N	\N
539	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:39.74691	t	\N	\N	\N
555	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.388119	t	\N	\N	\N
556	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.559985	t	\N	\N	\N
557	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.63811	t	\N	\N	\N
558	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:46.856901	t	\N	\N	\N
559	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:44.529001	t	\N	\N	\N
561	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:44.87314	t	\N	\N	\N
562	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:45.047354	t	\N	\N	\N
563	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:45.278731	t	\N	\N	\N
564	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:45.497465	t	\N	\N	\N
566	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:46.606936	t	\N	\N	\N
541	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:40.575445	t	\N	\N	\N
544	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:41.560152	t	\N	\N	\N
547	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:42.514023	t	\N	\N	\N
552	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.200627	t	\N	\N	\N
540	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:40.38795	t	\N	\N	\N
548	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:42.539107	t	\N	\N	\N
549	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:42.856507	t	\N	\N	\N
560	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:44.716882	t	\N	\N	\N
578	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:53.143328	t	\N	\N	\N
588	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:56.225266	t	\N	\N	\N
592	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:56.756495	t	\N	\N	\N
608	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.758087	t	\N	\N	\N
629	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:05.370731	t	\N	\N	\N
638	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.855888	t	\N	\N	\N
643	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.262123	t	\N	\N	\N
542	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:40.622318	t	\N	\N	\N
546	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:41.794526	t	\N	\N	\N
570	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:48.716963	t	\N	\N	\N
571	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:49.232452	t	\N	\N	\N
573	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:50.202318	t	\N	\N	\N
579	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:53.206183	t	\N	\N	\N
594	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.257155	t	\N	\N	\N
596	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.554022	t	\N	\N	\N
606	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.639174	t	\N	\N	\N
613	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:00.539458	t	\N	\N	\N
617	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.196117	t	\N	\N	\N
623	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:03.243089	t	\N	\N	\N
624	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:03.618354	t	\N	\N	\N
630	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:06.41757	t	\N	\N	\N
661	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:12.201339	t	\N	\N	\N
670	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:15.468578	t	\N	\N	\N
676	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.672323	t	\N	\N	\N
680	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.01724	t	\N	\N	\N
690	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:21.784052	t	\N	\N	\N
543	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:41.278972	t	\N	\N	\N
545	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:41.794526	t	\N	\N	\N
554	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:43.356867	t	\N	\N	\N
565	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:46.138088	t	\N	\N	\N
577	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:51.781368	t	\N	\N	\N
580	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:53.315542	t	\N	\N	\N
597	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.819642	t	\N	\N	\N
616	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:01.946122	t	\N	\N	\N
626	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:04.228863	t	\N	\N	\N
628	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:04.979388	t	\N	\N	\N
631	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:06.589865	t	\N	\N	\N
641	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.074629	t	\N	\N	\N
646	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.793353	t	\N	\N	\N
649	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:10.075299	t	\N	\N	\N
651	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:10.638231	t	\N	\N	\N
658	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.700917	t	\N	\N	\N
675	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.406394	t	\N	\N	\N
567	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:47.122529	t	\N	\N	\N
589	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:56.287765	t	\N	\N	\N
603	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.195396	t	\N	\N	\N
610	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.961199	t	\N	\N	\N
622	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.992789	t	\N	\N	\N
632	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:06.839861	t	\N	\N	\N
635	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.340284	t	\N	\N	\N
642	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.2465	t	\N	\N	\N
648	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:09.512516	t	\N	\N	\N
656	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.263423	t	\N	\N	\N
683	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.45503	t	\N	\N	\N
671	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:15.859195	t	\N	\N	\N
568	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:47.48222	t	\N	\N	\N
576	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:51.718872	t	\N	\N	\N
584	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:54.756433	t	\N	\N	\N
586	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:55.69325	t	\N	\N	\N
591	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:56.709628	t	\N	\N	\N
595	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.366533	t	\N	\N	\N
601	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:58.867283	t	\N	\N	\N
612	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:00.476953	t	\N	\N	\N
615	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:01.305131	t	\N	\N	\N
620	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.836655	t	\N	\N	\N
625	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:03.680846	t	\N	\N	\N
637	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.652779	t	\N	\N	\N
660	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:12.029474	t	\N	\N	\N
663	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:12.811049	t	\N	\N	\N
666	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:13.952117	t	\N	\N	\N
667	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:14.546387	t	\N	\N	\N
681	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.220358	t	\N	\N	\N
686	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:20.627664	t	\N	\N	\N
691	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:22.690607	t	\N	\N	\N
697	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:23.535305	t	\N	\N	\N
701	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:24.817762	t	\N	\N	\N
633	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.011729	t	\N	\N	\N
636	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.465272	t	\N	\N	\N
639	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.934016	t	\N	\N	\N
645	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.496499	t	\N	\N	\N
647	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:09.340641	t	\N	\N	\N
655	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.013018	t	\N	\N	\N
669	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:14.593265	t	\N	\N	\N
672	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.124812	t	\N	\N	\N
600	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:58.632544	t	\N	\N	\N
602	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.195396	t	\N	\N	\N
575	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:51.59344	t	\N	\N	\N
693	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:22.831562	t	\N	\N	\N
583	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:54.644529	t	\N	\N	\N
618	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.571099	t	\N	\N	\N
585	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:55.490132	t	\N	\N	\N
569	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:48.091987	t	\N	\N	\N
581	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:54.503497	t	\N	\N	\N
590	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:56.412756	t	\N	\N	\N
598	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.944633	t	\N	\N	\N
604	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.508093	t	\N	\N	\N
609	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.945575	t	\N	\N	\N
611	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:00.305087	t	\N	\N	\N
657	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.544666	t	\N	\N	\N
677	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.750436	t	\N	\N	\N
685	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:20.346359	t	\N	\N	\N
696	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:23.441563	t	\N	\N	\N
700	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:24.53149	t	\N	\N	\N
572	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:49.248082	t	\N	\N	\N
593	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:57.116544	t	\N	\N	\N
605	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.61746	t	\N	\N	\N
607	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:59.726833	t	\N	\N	\N
627	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:04.228863	t	\N	\N	\N
640	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.996515	t	\N	\N	\N
644	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:08.433993	t	\N	\N	\N
652	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:10.841345	t	\N	\N	\N
665	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:13.795868	t	\N	\N	\N
673	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.140449	t	\N	\N	\N
678	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:18.251178	t	\N	\N	\N
679	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.001615	t	\N	\N	\N
688	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:21.190463	t	\N	\N	\N
695	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:23.191305	t	\N	\N	\N
698	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:24.286132	t	\N	\N	\N
699	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:24.473627	t	\N	\N	\N
702	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:24.833383	t	\N	\N	\N
574	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:51.468452	t	\N	\N	\N
582	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:54.597656	t	\N	\N	\N
634	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:07.152807	t	\N	\N	\N
653	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:10.888225	t	\N	\N	\N
674	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:16.37515	t	\N	\N	\N
684	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.501902	t	\N	\N	\N
703	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:25.364611	t	\N	\N	\N
587	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:55.771364	t	\N	\N	\N
599	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:32:58.054006	t	\N	\N	\N
614	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:01.117648	t	\N	\N	\N
619	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.673067	t	\N	\N	\N
621	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:02.94591	t	\N	\N	\N
650	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:10.512791	t	\N	\N	\N
654	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.216533	t	\N	\N	\N
662	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:12.779788	t	\N	\N	\N
664	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:13.717745	t	\N	\N	\N
668	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:14.562017	t	\N	\N	\N
682	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:19.392527	t	\N	\N	\N
687	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:20.830803	t	\N	\N	\N
689	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:21.690304	t	\N	\N	\N
692	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:22.831562	t	\N	\N	\N
694	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:23.050682	t	\N	\N	\N
659	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:11.82635	t	\N	\N	\N
704	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.208611	t	\N	\N	\N
705	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.286731	t	\N	\N	\N
706	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.427351	t	\N	\N	\N
707	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.427351	t	\N	\N	\N
708	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.47423	t	\N	\N	\N
709	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:26.4586	t	\N	\N	\N
710	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:27.229918	t	\N	\N	\N
711	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:27.334212	t	\N	\N	\N
712	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:27.334212	t	\N	\N	\N
713	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:27.725236	t	\N	\N	\N
714	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:27.975601	t	\N	\N	\N
715	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:28.163122	t	\N	\N	\N
716	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:28.569798	t	\N	\N	\N
717	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:28.647917	t	\N	\N	\N
718	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:28.819999	t	\N	\N	\N
719	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:29.820398	t	\N	\N	\N
720	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:29.78915	t	\N	\N	\N
721	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:29.914147	t	\N	\N	\N
722	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:29.945394	t	\N	\N	\N
723	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:30.446384	t	\N	\N	\N
724	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:30.931439	t	\N	\N	\N
725	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:30.993954	t	\N	\N	\N
726	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:31.588737	t	\N	\N	\N
727	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:31.619988	t	\N	\N	\N
728	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:31.635612	t	\N	\N	\N
729	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:31.74498	t	\N	\N	\N
730	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:32.464131	t	\N	\N	\N
731	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:32.948667	t	\N	\N	\N
732	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:33.104916	t	\N	\N	\N
733	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:33.245966	t	\N	\N	\N
734	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:33.542833	t	\N	\N	\N
735	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:33.652299	t	\N	\N	\N
736	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:34.40356	t	\N	\N	\N
737	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:34.544172	t	\N	\N	\N
738	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:34.700426	t	\N	\N	\N
739	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:34.788653	t	\N	\N	\N
740	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:35.43529	t	\N	\N	\N
752	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:38.031445	t	\N	\N	\N
754	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:38.860358	t	\N	\N	\N
741	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:35.670413	t	\N	\N	\N
755	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:39.173286	t	\N	\N	\N
756	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:39.282937	t	\N	\N	\N
757	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:39.830278	t	\N	\N	\N
742	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:35.842279	t	\N	\N	\N
743	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:36.014148	t	\N	\N	\N
758	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:39.799033	t	\N	\N	\N
744	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:36.092269	t	\N	\N	\N
760	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:40.517752	t	\N	\N	\N
761	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:40.877109	t	\N	\N	\N
762	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:41.549009	t	\N	\N	\N
745	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:36.452035	t	\N	\N	\N
763	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:42.03336	t	\N	\N	\N
764	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:42.080232	t	\N	\N	\N
746	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:36.670782	t	\N	\N	\N
765	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:42.862421	t	\N	\N	\N
747	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:36.765097	t	\N	\N	\N
766	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:43.472194	t	\N	\N	\N
767	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:43.988675	t	\N	\N	\N
768	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:44.066801	t	\N	\N	\N
748	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:37.077787	t	\N	\N	\N
769	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:44.160552	t	\N	\N	\N
770	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:44.426464	t	\N	\N	\N
749	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:37.43759	t	\N	\N	\N
750	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:37.468834	t	\N	\N	\N
771	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:44.489415	t	\N	\N	\N
772	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.067513	t	\N	\N	\N
773	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.098767	t	\N	\N	\N
774	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.224238	t	\N	\N	\N
775	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.364862	t	\N	\N	\N
798	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:54.510028	t	\N	\N	\N
802	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:55.83854	t	\N	\N	\N
821	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:04.497628	t	\N	\N	\N
834	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.357723	t	\N	\N	\N
869	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:16.050034	t	\N	\N	\N
887	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:22.929631	t	\N	\N	\N
751	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:37.703332	t	\N	\N	\N
753	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:38.172064	t	\N	\N	\N
759	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:39.924031	t	\N	\N	\N
787	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:49.023035	t	\N	\N	\N
814	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:01.715699	t	\N	\N	\N
819	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:03.95034	t	\N	\N	\N
832	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.279601	t	\N	\N	\N
839	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:08.953151	t	\N	\N	\N
842	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:09.766733	t	\N	\N	\N
855	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:12.064462	t	\N	\N	\N
857	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:12.502196	t	\N	\N	\N
776	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.59922	t	\N	\N	\N
788	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:49.054291	t	\N	\N	\N
791	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:51.070817	t	\N	\N	\N
792	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:51.930579	t	\N	\N	\N
793	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:52.775114	t	\N	\N	\N
800	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:55.010422	t	\N	\N	\N
836	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.999291	t	\N	\N	\N
847	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.329511	t	\N	\N	\N
851	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.751387	t	\N	\N	\N
852	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:11.173743	t	\N	\N	\N
866	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:14.753007	t	\N	\N	\N
873	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:17.285569	t	\N	\N	\N
881	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:20.052554	t	\N	\N	\N
891	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:24.039111	t	\N	\N	\N
777	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.708605	t	\N	\N	\N
779	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.974216	t	\N	\N	\N
781	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:46.708957	t	\N	\N	\N
783	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:47.240198	t	\N	\N	\N
799	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:54.666266	t	\N	\N	\N
801	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:55.557293	t	\N	\N	\N
815	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:01.731322	t	\N	\N	\N
840	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:09.385199	t	\N	\N	\N
844	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:09.860491	t	\N	\N	\N
846	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.285484	t	\N	\N	\N
859	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:12.908432	t	\N	\N	\N
864	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:14.424894	t	\N	\N	\N
778	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:45.755466	t	\N	\N	\N
780	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:46.02108	t	\N	\N	\N
784	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:48.178459	t	\N	\N	\N
785	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:48.428453	t	\N	\N	\N
790	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:50.804771	t	\N	\N	\N
795	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:53.556512	t	\N	\N	\N
803	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:55.869784	t	\N	\N	\N
806	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:58.074056	t	\N	\N	\N
817	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:02.590666	t	\N	\N	\N
824	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:05.091431	t	\N	\N	\N
828	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:06.623134	t	\N	\N	\N
853	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:11.439484	t	\N	\N	\N
861	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:13.252184	t	\N	\N	\N
863	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:14.268651	t	\N	\N	\N
885	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:21.19357	t	\N	\N	\N
895	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:25.180699	t	\N	\N	\N
805	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:57.276817	t	\N	\N	\N
810	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:59.621474	t	\N	\N	\N
838	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:08.197301	t	\N	\N	\N
841	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:09.406855	t	\N	\N	\N
849	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.438886	t	\N	\N	\N
880	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:19.333389	t	\N	\N	\N
782	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:47.037078	t	\N	\N	\N
786	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:49.023035	t	\N	\N	\N
797	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:54.431899	t	\N	\N	\N
825	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:05.169558	t	\N	\N	\N
827	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:06.560637	t	\N	\N	\N
835	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.576575	t	\N	\N	\N
837	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:08.030534	t	\N	\N	\N
854	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:11.955096	t	\N	\N	\N
856	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:12.251953	t	\N	\N	\N
860	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:13.064679	t	\N	\N	\N
862	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:14.049276	t	\N	\N	\N
865	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:14.456146	t	\N	\N	\N
884	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:20.630928	t	\N	\N	\N
892	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:24.148488	t	\N	\N	\N
789	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:50.351126	t	\N	\N	\N
804	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:55.916666	t	\N	\N	\N
807	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:58.637037	t	\N	\N	\N
812	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:01.527787	t	\N	\N	\N
816	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:02.559417	t	\N	\N	\N
820	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:04.075757	t	\N	\N	\N
833	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.326469	t	\N	\N	\N
843	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:09.829242	t	\N	\N	\N
845	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.157347	t	\N	\N	\N
868	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:15.987535	t	\N	\N	\N
872	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:17.191557	t	\N	\N	\N
874	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:17.285569	t	\N	\N	\N
876	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:17.707896	t	\N	\N	\N
877	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:18.457891	t	\N	\N	\N
883	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:20.589551	t	\N	\N	\N
889	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:23.945362	t	\N	\N	\N
893	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:24.414098	t	\N	\N	\N
896	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:25.383821	t	\N	\N	\N
794	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:53.243871	t	\N	\N	\N
796	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:54.385023	t	\N	\N	\N
808	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:58.808997	t	\N	\N	\N
811	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:00.21484	t	\N	\N	\N
813	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:01.700069	t	\N	\N	\N
818	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:02.73129	t	\N	\N	\N
823	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:04.982058	t	\N	\N	\N
826	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:05.450794	t	\N	\N	\N
829	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:06.638758	t	\N	\N	\N
850	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.626377	t	\N	\N	\N
870	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:16.510225	t	\N	\N	\N
871	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:16.878624	t	\N	\N	\N
875	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:17.676231	t	\N	\N	\N
886	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:22.616875	t	\N	\N	\N
888	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:21.219252	t	\N	\N	\N
890	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:24.02349	t	\N	\N	\N
858	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:12.502196	t	\N	\N	\N
867	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:15.768345	t	\N	\N	\N
878	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:18.504768	t	\N	\N	\N
822	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:04.388251	t	\N	\N	\N
830	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:06.795004	t	\N	\N	\N
831	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:07.092103	t	\N	\N	\N
809	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:33:58.902749	t	\N	\N	\N
848	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:10.360764	t	\N	\N	\N
922	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:36.029584	t	\N	\N	\N
901	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:27.416035	t	\N	\N	\N
917	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:31.340338	t	\N	\N	\N
902	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:27.572278	t	\N	\N	\N
931	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:39.250533	t	\N	\N	\N
903	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:27.650402	t	\N	\N	\N
960	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:49.225769	t	\N	\N	\N
938	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:41.626696	t	\N	\N	\N
944	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:43.736433	t	\N	\N	\N
879	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:19.255282	t	\N	\N	\N
939	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:42.017312	t	\N	\N	\N
932	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:39.954048	t	\N	\N	\N
904	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:28.369553	t	\N	\N	\N
882	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:20.2088	t	\N	\N	\N
923	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:36.577261	t	\N	\N	\N
952	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:46.753982	t	\N	\N	\N
918	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:32.403618	t	\N	\N	\N
905	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:28.620462	t	\N	\N	\N
924	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:36.577261	t	\N	\N	\N
906	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:28.808468	t	\N	\N	\N
925	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:36.639747	t	\N	\N	\N
907	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:28.8241	t	\N	\N	\N
933	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:40.219667	t	\N	\N	\N
940	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:42.673774	t	\N	\N	\N
947	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:44.893626	t	\N	\N	\N
908	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:29.121033	t	\N	\N	\N
934	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:40.344659	t	\N	\N	\N
909	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:29.183529	t	\N	\N	\N
919	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:33.044935	t	\N	\N	\N
949	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:45.706969	t	\N	\N	\N
926	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:37.968451	t	\N	\N	\N
910	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:29.574149	t	\N	\N	\N
927	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:38.015323	t	\N	\N	\N
911	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:29.714899	t	\N	\N	\N
920	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:33.841791	t	\N	\N	\N
928	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:38.421937	t	\N	\N	\N
945	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:44.455977	t	\N	\N	\N
894	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:25.086958	t	\N	\N	\N
921	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:34.498302	t	\N	\N	\N
948	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:45.206111	t	\N	\N	\N
912	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:30.46536	t	\N	\N	\N
935	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:41.079689	t	\N	\N	\N
953	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:46.894601	t	\N	\N	\N
946	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:44.580978	t	\N	\N	\N
913	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:30.605987	t	\N	\N	\N
941	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:43.267691	t	\N	\N	\N
897	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:26.244016	t	\N	\N	\N
929	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:38.734851	t	\N	\N	\N
914	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:30.965347	t	\N	\N	\N
898	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:26.790997	t	\N	\N	\N
915	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:30.996601	t	\N	\N	\N
936	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:41.251558	t	\N	\N	\N
899	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:27.025421	t	\N	\N	\N
937	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:41.251558	t	\N	\N	\N
900	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:27.05668	t	\N	\N	\N
954	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:47.019605	t	\N	\N	\N
916	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:31.074715	t	\N	\N	\N
930	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:38.797353	t	\N	\N	\N
964	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:49.941715	t	\N	\N	\N
965	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:50.316706	t	\N	\N	\N
942	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:43.40832	t	\N	\N	\N
950	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:46.0976	t	\N	\N	\N
943	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:43.548942	t	\N	\N	\N
955	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:47.316466	t	\N	\N	\N
951	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:46.535242	t	\N	\N	\N
966	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:50.707777	t	\N	\N	\N
956	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:47.332097	t	\N	\N	\N
957	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:47.410222	t	\N	\N	\N
967	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:50.832778	t	\N	\N	\N
968	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.270252	t	\N	\N	\N
993	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:00.150228	t	\N	\N	\N
1005	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:03.385271	t	\N	\N	\N
1018	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:10.655352	t	\N	\N	\N
1029	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:14.859966	t	\N	\N	\N
1046	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:20.111063	t	\N	\N	\N
1050	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:21.158065	t	\N	\N	\N
1056	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.64299	t	\N	\N	\N
962	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:49.332358	t	\N	\N	\N
963	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:49.863591	t	\N	\N	\N
958	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:48.097686	t	\N	\N	\N
991	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:58.868818	t	\N	\N	\N
995	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:00.822372	t	\N	\N	\N
998	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:01.244503	t	\N	\N	\N
1015	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:07.372807	t	\N	\N	\N
1021	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:11.624656	t	\N	\N	\N
1026	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:13.891103	t	\N	\N	\N
1032	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:15.532161	t	\N	\N	\N
1034	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:15.829018	t	\N	\N	\N
1036	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.188383	t	\N	\N	\N
1039	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.313379	t	\N	\N	\N
1042	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:18.220242	t	\N	\N	\N
1051	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:21.470562	t	\N	\N	\N
959	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:48.472677	t	\N	\N	\N
961	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:49.227833	t	\N	\N	\N
969	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.348374	t	\N	\N	\N
974	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.7874	t	\N	\N	\N
1007	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:04.589436	t	\N	\N	\N
1012	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:06.325311	t	\N	\N	\N
1016	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:07.70093	t	\N	\N	\N
1024	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:12.515344	t	\N	\N	\N
970	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.364001	t	\N	\N	\N
976	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:52.864405	t	\N	\N	\N
989	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.930517	t	\N	\N	\N
996	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:01.025736	t	\N	\N	\N
1006	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:04.323819	t	\N	\N	\N
1009	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:05.465656	t	\N	\N	\N
1014	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:06.966155	t	\N	\N	\N
1022	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:11.702786	t	\N	\N	\N
1047	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:20.53292	t	\N	\N	\N
1055	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.517994	t	\N	\N	\N
1060	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:24.425569	t	\N	\N	\N
971	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.55176	t	\N	\N	\N
987	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.711343	t	\N	\N	\N
1001	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:02.728757	t	\N	\N	\N
1004	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:03.322773	t	\N	\N	\N
1019	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:11.264781	t	\N	\N	\N
1052	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:21.642594	t	\N	\N	\N
972	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.614257	t	\N	\N	\N
975	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:52.786286	t	\N	\N	\N
983	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.054913	t	\N	\N	\N
997	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:01.057004	t	\N	\N	\N
1000	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:02.666259	t	\N	\N	\N
1011	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:06.059694	t	\N	\N	\N
1037	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.141513	t	\N	\N	\N
1043	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:19.376721	t	\N	\N	\N
1048	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:20.658081	t	\N	\N	\N
1049	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:21.079942	t	\N	\N	\N
1053	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.049255	t	\N	\N	\N
1057	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.611738	t	\N	\N	\N
1061	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:25.28563	t	\N	\N	\N
973	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:51.661151	t	\N	\N	\N
977	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:53.864833	t	\N	\N	\N
988	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.773844	t	\N	\N	\N
1002	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:02.822771	t	\N	\N	\N
1010	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:05.809693	t	\N	\N	\N
1017	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:07.982665	t	\N	\N	\N
1020	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:11.562165	t	\N	\N	\N
1033	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:15.579032	t	\N	\N	\N
1045	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:19.47046	t	\N	\N	\N
1054	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.330501	t	\N	\N	\N
1058	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:22.877589	t	\N	\N	\N
978	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:54.693529	t	\N	\N	\N
982	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:55.77326	t	\N	\N	\N
984	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.179917	t	\N	\N	\N
985	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.289285	t	\N	\N	\N
1003	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:02.947792	t	\N	\N	\N
1027	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:14.094367	t	\N	\N	\N
1038	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.313379	t	\N	\N	\N
1041	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.532203	t	\N	\N	\N
979	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:54.865396	t	\N	\N	\N
980	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:55.068859	t	\N	\N	\N
981	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:55.163452	t	\N	\N	\N
1008	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:04.933497	t	\N	\N	\N
990	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:57.930665	t	\N	\N	\N
1031	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:15.063083	t	\N	\N	\N
1040	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:16.407132	t	\N	\N	\N
999	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:02.338151	t	\N	\N	\N
986	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:56.55511	t	\N	\N	\N
992	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:34:59.478275	t	\N	\N	\N
994	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:00.728621	t	\N	\N	\N
1013	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:06.778423	t	\N	\N	\N
1023	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:12.124643	t	\N	\N	\N
1025	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:12.68721	t	\N	\N	\N
1028	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:14.21936	t	\N	\N	\N
1030	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:14.906842	t	\N	\N	\N
1035	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:15.860273	t	\N	\N	\N
1044	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:19.173597	t	\N	\N	\N
1059	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:23.487696	t	\N	\N	\N
1062	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:25.863952	t	\N	\N	\N
1063	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:25.957709	t	\N	\N	\N
1064	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.176649	t	\N	\N	\N
1065	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.207896	t	\N	\N	\N
1066	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.270396	t	\N	\N	\N
1067	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.629886	t	\N	\N	\N
1068	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.692378	t	\N	\N	\N
1069	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.770505	t	\N	\N	\N
1070	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:26.848623	t	\N	\N	\N
1071	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:27.395792	t	\N	\N	\N
1072	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:28.395778	t	\N	\N	\N
1073	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:29.458774	t	\N	\N	\N
1074	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:29.787343	t	\N	\N	\N
1075	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:29.9592	t	\N	\N	\N
1076	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:30.490438	t	\N	\N	\N
1077	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:31.396991	t	\N	\N	\N
1078	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:31.52243	t	\N	\N	\N
1079	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:31.881815	t	\N	\N	\N
1080	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:31.929105	t	\N	\N	\N
1081	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:32.054121	t	\N	\N	\N
1082	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:32.679566	t	\N	\N	\N
1083	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:32.851849	t	\N	\N	\N
1084	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:34.070586	t	\N	\N	\N
1085	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:34.539318	t	\N	\N	\N
1086	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.070803	t	\N	\N	\N
1087	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.414559	t	\N	\N	\N
1088	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.587379	t	\N	\N	\N
1089	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.602995	t	\N	\N	\N
1090	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.696744	t	\N	\N	\N
1091	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:35.712375	t	\N	\N	\N
1092	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:36.384225	t	\N	\N	\N
1093	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:37.088231	t	\N	\N	\N
1094	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:37.181985	t	\N	\N	\N
1095	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:37.603833	t	\N	\N	\N
1096	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:37.697587	t	\N	\N	\N
1097	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:37.822577	t	\N	\N	\N
1098	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:38.448274	t	\N	\N	\N
1099	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:38.463914	t	\N	\N	\N
1100	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:38.698277	t	\N	\N	\N
1101	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:39.026395	t	\N	\N	\N
1102	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.683826	t	\N	\N	\N
1103	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:39.667695	t	\N	\N	\N
1104	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:39.82396	t	\N	\N	\N
1105	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:40.667689	t	\N	\N	\N
1106	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.105424	t	\N	\N	\N
1107	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.308541	t	\N	\N	\N
1108	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.902559	t	\N	\N	\N
1109	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.996517	t	\N	\N	\N
1110	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:41.996517	t	\N	\N	\N
1111	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:42.152757	t	\N	\N	\N
1112	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:42.574618	t	\N	\N	\N
1113	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:43.137107	t	\N	\N	\N
1114	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:43.402727	t	\N	\N	\N
1115	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:43.840493	t	\N	\N	\N
1116	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:44.090501	t	\N	\N	\N
1117	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:44.184238	t	\N	\N	\N
1118	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:44.716779	t	\N	\N	\N
1119	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:44.85739	t	\N	\N	\N
1120	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:44.888639	t	\N	\N	\N
1121	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:47.531349	t	\N	\N	\N
1124	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:48.234801	t	\N	\N	\N
1135	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.361415	t	\N	\N	\N
1138	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.736528	t	\N	\N	\N
1142	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:53.205262	t	\N	\N	\N
1146	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:54.567261	t	\N	\N	\N
1171	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:01.882012	t	\N	\N	\N
1179	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:04.022904	t	\N	\N	\N
1196	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:13.933796	t	\N	\N	\N
1198	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:14.574369	t	\N	\N	\N
1207	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.809465	t	\N	\N	\N
1213	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:17.434868	t	\N	\N	\N
1222	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.732456	t	\N	\N	\N
1228	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:23.905446	t	\N	\N	\N
1122	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:48.14105	t	\N	\N	\N
1132	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:50.766779	t	\N	\N	\N
1141	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.92402	t	\N	\N	\N
1191	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:11.307556	t	\N	\N	\N
1202	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:15.88724	t	\N	\N	\N
1217	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:19.826024	t	\N	\N	\N
1223	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.911414	t	\N	\N	\N
1123	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:48.219178	t	\N	\N	\N
1126	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:48.656664	t	\N	\N	\N
1143	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:53.518004	t	\N	\N	\N
1168	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:00.554165	t	\N	\N	\N
1186	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:09.197324	t	\N	\N	\N
1187	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:09.644729	t	\N	\N	\N
1193	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:11.510676	t	\N	\N	\N
1203	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.278071	t	\N	\N	\N
1211	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:17.356751	t	\N	\N	\N
1216	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:19.747905	t	\N	\N	\N
1218	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:20.919748	t	\N	\N	\N
1125	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:48.500425	t	\N	\N	\N
1137	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.642648	t	\N	\N	\N
1160	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:58.240873	t	\N	\N	\N
1163	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:59.413159	t	\N	\N	\N
1165	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:59.991264	t	\N	\N	\N
1184	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:07.165263	t	\N	\N	\N
1188	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:10.60419	t	\N	\N	\N
1189	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:10.60419	t	\N	\N	\N
1204	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.340569	t	\N	\N	\N
1206	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.746964	t	\N	\N	\N
1212	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:17.419244	t	\N	\N	\N
1221	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.669964	t	\N	\N	\N
1224	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.982539	t	\N	\N	\N
1127	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:49.641257	t	\N	\N	\N
1131	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:50.766779	t	\N	\N	\N
1149	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:55.473762	t	\N	\N	\N
1153	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:56.850151	t	\N	\N	\N
1174	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:03.053856	t	\N	\N	\N
1178	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:03.960408	t	\N	\N	\N
1182	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:04.288522	t	\N	\N	\N
1183	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:05.366992	t	\N	\N	\N
1214	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:18.169592	t	\N	\N	\N
1226	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:22.561063	t	\N	\N	\N
1128	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:49.641257	t	\N	\N	\N
1129	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:50.078744	t	\N	\N	\N
1130	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:50.688655	t	\N	\N	\N
1151	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:56.254977	t	\N	\N	\N
1157	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:57.959571	t	\N	\N	\N
1159	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:58.131445	t	\N	\N	\N
1166	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:00.085009	t	\N	\N	\N
1173	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:02.194513	t	\N	\N	\N
1181	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:04.210398	t	\N	\N	\N
1194	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:12.495011	t	\N	\N	\N
1197	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:14.090034	t	\N	\N	\N
1205	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.496973	t	\N	\N	\N
1208	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.825085	t	\N	\N	\N
1220	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.435359	t	\N	\N	\N
1133	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:50.766779	t	\N	\N	\N
1136	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.627024	t	\N	\N	\N
1158	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:57.975195	t	\N	\N	\N
1164	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:59.553772	t	\N	\N	\N
1176	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:03.163224	t	\N	\N	\N
1180	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:04.194774	t	\N	\N	\N
1219	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:21.544719	t	\N	\N	\N
1134	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:51.266856	t	\N	\N	\N
1140	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.845893	t	\N	\N	\N
1144	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:53.705755	t	\N	\N	\N
1145	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:54.207915	t	\N	\N	\N
1156	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:57.912697	t	\N	\N	\N
1167	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:00.381876	t	\N	\N	\N
1169	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:00.866651	t	\N	\N	\N
1177	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:03.66321	t	\N	\N	\N
1195	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:12.588768	t	\N	\N	\N
1199	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:14.886858	t	\N	\N	\N
1201	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:15.559124	t	\N	\N	\N
1209	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:16.934463	t	\N	\N	\N
1215	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:19.357119	t	\N	\N	\N
1225	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:22.248167	t	\N	\N	\N
1139	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:52.830274	t	\N	\N	\N
1147	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:54.770387	t	\N	\N	\N
1148	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:55.20787	t	\N	\N	\N
1150	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:55.801879	t	\N	\N	\N
1154	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:57.772074	t	\N	\N	\N
1170	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:01.335166	t	\N	\N	\N
1185	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:07.728164	t	\N	\N	\N
1190	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:11.026317	t	\N	\N	\N
1200	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:14.964979	t	\N	\N	\N
1210	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:17.04434	t	\N	\N	\N
1152	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:56.489764	t	\N	\N	\N
1155	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:57.834578	t	\N	\N	\N
1161	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:58.459617	t	\N	\N	\N
1162	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:35:59.100671	t	\N	\N	\N
1172	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:01.63203	t	\N	\N	\N
1175	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:03.100727	t	\N	\N	\N
1192	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:11.416937	t	\N	\N	\N
1227	Marlon	292901192	DNI	Costa Rica	88888888	juan@example.com	2025-06-29 07:36:22.764181	t	\N	\N	\N
\.


--
-- TOC entry 4227 (class 0 OID 25410)
-- Dependencies: 219
-- Data for Name: facturas; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.facturas (factura_id, pago_id, hotel_id, numero_factura, fecha_emision, subtotal, impuestos, total, datos_cliente, detalles) FROM stdin;
\.


--
-- TOC entry 4229 (class 0 OID 25416)
-- Dependencies: 221
-- Data for Name: fidelizacion_clientes; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.fidelizacion_clientes (fidelizacion_id, cliente_id, hotel_id, puntos_acumulados, nivel_membresia, beneficios, fecha_actualizacion) FROM stdin;
1	1	1	500	Oro	Check-out tardio, upgrades gratuitos	2025-05-20 22:14:34.722928
\.


--
-- TOC entry 4231 (class 0 OID 25424)
-- Dependencies: 223
-- Data for Name: habitaciones; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.habitaciones (habitacion_id, hotel_id, numero, tipo_id, piso, caracteristicas_especiales, estado, notas, precio_habitacion, esta_ocupada, descripcion) FROM stdin;
1	1	101	1	1	Vista al jardin	ocupada	\N	\N	f	\N
2	1	102	1	1	\N	disponible	\N	\N	t	\N
3	1	201	2	2	Balcon	disponible	\N	\N	t	\N
4	1	104	\N	1	\N	disponible	\N	99.99	f	Habitaci¢n est ndar
5	1	105	3	1	\N	disponible	\N	39.99	f	Con vista al valcon
\.


--
-- TOC entry 4233 (class 0 OID 25431)
-- Dependencies: 225
-- Data for Name: historico_estadias; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.historico_estadias (historico_id, hotel_id, cliente_id, reservacion_id, fecha_entrada, fecha_salida, habitacion_id, comentarios, calificacion, preferencias_registradas) FROM stdin;
\.


--
-- TOC entry 4235 (class 0 OID 25438)
-- Dependencies: 227
-- Data for Name: hoteles; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.hoteles (hotel_id, nombre, direccion, ciudad, pais, telefono, email, estrellas, activo, fecha_apertura, descripcion) FROM stdin;
1	Hotel Central	Av. Principal 123	San Jose	Costa Rica	2222-1111	central@hotel.com	4	t	2020-01-01	Hotel de lujo en el centro
\.


--
-- TOC entry 4237 (class 0 OID 25446)
-- Dependencies: 229
-- Data for Name: pagos; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.pagos (pago_id, reservacion_id, monto, metodo_pago, fecha_pago, estado, referencia, descripcion) FROM stdin;
1	5	100.00	Tarjeta	2025-05-20 22:30:34.031821	pendiente	\N	\N
\.


--
-- TOC entry 4239 (class 0 OID 25454)
-- Dependencies: 231
-- Data for Name: politicas_temporada; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.politicas_temporada (politica_id, hotel_id, nombre, fecha_inicio, fecha_fin, descripcion, reglas) FROM stdin;
1	1	Temporada Alta	2025-12-01	2026-01-31	Alt¶¡sima demanda	Reservas no reembolsables
\.


--
-- TOC entry 4241 (class 0 OID 25461)
-- Dependencies: 233
-- Data for Name: reservacion_habitaciones; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.reservacion_habitaciones (detalle_id, reservacion_id, habitacion_id, tarifa_aplicada, notas) FROM stdin;
1	4	1	100.00	Asignaci¶¢n inicial
2	5	1	100.00	Asignaci¶¢n inicial
4	17	5	120.50	Reservaci¢n inicial
\.


--
-- TOC entry 4243 (class 0 OID 25467)
-- Dependencies: 235
-- Data for Name: reservacion_servicios; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.reservacion_servicios (detalle_servicio_id, reservacion_id, servicio_id, tipo_servicio, descripcion, fecha_servicio, cantidad, precio_unitario, notas, estado) FROM stdin;
\.


--
-- TOC entry 4245 (class 0 OID 25476)
-- Dependencies: 237
-- Data for Name: reservaciones; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.reservaciones (reservacion_id, hotel_id, cliente_id, fecha_creacion, fecha_entrada, fecha_salida, estado, tipo_reserva, solicitudes_especiales, codigo_reserva, huespedes) FROM stdin;
4	1	1	2025-05-20 22:23:10.984702	2025-12-15	2025-12-20	cancelada	individual	Necesita cuna	RES-1-2025-9739	\N
5	1	1	2025-05-20 22:29:42.72008	2025-12-13	2025-12-23	confirmada	grupo	Necesita cuna	RES-1-2025-7587	\N
12	1	7	2025-06-12 10:24:52.650148	2024-11-15	2025-11-20	confirmada	grupo	Quisiera una habitaci¢n con vista al mar y cama king size	\N	\N
17	\N	2	2025-06-23 18:40:14.341023	2025-07-10	2025-07-12	pendiente	individual	Sin solicitudes especiales	\N	3
\.


--
-- TOC entry 4247 (class 0 OID 25488)
-- Dependencies: 239
-- Data for Name: servicios_hotel; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.servicios_hotel (servicio_id, hotel_id, nombre, descripcion, precio_base, categoria, horario_disponibilidad, activo) FROM stdin;
\.


--
-- TOC entry 4249 (class 0 OID 25495)
-- Dependencies: 241
-- Data for Name: tarifas_temporada; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.tarifas_temporada (tarifa_id, politica_id, tipo_id, precio, descripcion) FROM stdin;
1	1	1	100.00	Precio temporada alta - est¶ÿndar
2	1	2	200.00	Precio temporada alta - suite
\.


--
-- TOC entry 4251 (class 0 OID 25501)
-- Dependencies: 243
-- Data for Name: tipos_habitacion; Type: TABLE DATA; Schema: public; Owner: nechavarria
--

COPY public.tipos_habitacion (tipo_id, hotel_id, nombre, descripcion, capacidad, tamano, comodidades, precio_base) FROM stdin;
1	1	Est¶ÿndar	C¶¢moda habitaci¶¢n est¶ÿndar	2	20	TV, WiFi, A/C	70.00
2	1	Suite	Suite con sala	4	40	TV, WiFi, A/C, Sala	150.00
3	1	Generica	Generico, para prueba de carga	6	40	Todas las comodidades, uso generico de prueba	200.00
\.


--
-- TOC entry 4357 (class 0 OID 0)
-- Dependencies: 245
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.bitacora_reservaciones_bitacora_id_seq', 5, true);


--
-- TOC entry 4358 (class 0 OID 0)
-- Dependencies: 218
-- Name: clientes_cliente_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.clientes_cliente_id_seq', 1520, true);


--
-- TOC entry 4359 (class 0 OID 0)
-- Dependencies: 220
-- Name: facturas_factura_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.facturas_factura_id_seq', 1, false);


--
-- TOC entry 4360 (class 0 OID 0)
-- Dependencies: 222
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.fidelizacion_clientes_fidelizacion_id_seq', 1, false);


--
-- TOC entry 4361 (class 0 OID 0)
-- Dependencies: 224
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.habitaciones_habitacion_id_seq', 5, true);


--
-- TOC entry 4362 (class 0 OID 0)
-- Dependencies: 226
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.historico_estadias_historico_id_seq', 1, false);


--
-- TOC entry 4363 (class 0 OID 0)
-- Dependencies: 228
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.hoteles_hotel_id_seq', 1, false);


--
-- TOC entry 4364 (class 0 OID 0)
-- Dependencies: 230
-- Name: pagos_pago_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.pagos_pago_id_seq', 1, false);


--
-- TOC entry 4365 (class 0 OID 0)
-- Dependencies: 232
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.politicas_temporada_politica_id_seq', 1, false);


--
-- TOC entry 4366 (class 0 OID 0)
-- Dependencies: 234
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.reservacion_habitaciones_detalle_id_seq', 4, true);


--
-- TOC entry 4367 (class 0 OID 0)
-- Dependencies: 236
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.reservacion_servicios_detalle_servicio_id_seq', 1, false);


--
-- TOC entry 4368 (class 0 OID 0)
-- Dependencies: 238
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.reservaciones_reservacion_id_seq', 17, true);


--
-- TOC entry 4369 (class 0 OID 0)
-- Dependencies: 240
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.servicios_hotel_servicio_id_seq', 1, false);


--
-- TOC entry 4370 (class 0 OID 0)
-- Dependencies: 242
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.tarifas_temporada_tarifa_id_seq', 1, false);


--
-- TOC entry 4371 (class 0 OID 0)
-- Dependencies: 244
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nechavarria
--

SELECT pg_catalog.setval('public.tipos_habitacion_tipo_id_seq', 1, true);


--
-- TOC entry 4062 (class 2606 OID 25676)
-- Name: bitacora_reservaciones bitacora_reservaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.bitacora_reservaciones
    ADD CONSTRAINT bitacora_reservaciones_pkey PRIMARY KEY (bitacora_id);


--
-- TOC entry 4046 (class 2606 OID 25522)
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (cliente_id);


--
-- TOC entry 4048 (class 2606 OID 25524)
-- Name: facturas facturas_numero_factura_key; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_numero_factura_key UNIQUE (numero_factura);


--
-- TOC entry 4050 (class 2606 OID 25526)
-- Name: facturas facturas_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_pkey PRIMARY KEY (factura_id);


--
-- TOC entry 4052 (class 2606 OID 25528)
-- Name: fidelizacion_clientes fidelizacion_clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_pkey PRIMARY KEY (fidelizacion_id);


--
-- TOC entry 4054 (class 2606 OID 25530)
-- Name: habitaciones habitaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT habitaciones_pkey PRIMARY KEY (habitacion_id);


--
-- TOC entry 4056 (class 2606 OID 25532)
-- Name: historico_estadias historico_estadias_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_pkey PRIMARY KEY (historico_id);


--
-- TOC entry 4058 (class 2606 OID 25541)
-- Name: hoteles hoteles_pkey; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.hoteles
    ADD CONSTRAINT hoteles_pkey PRIMARY KEY (hotel_id);


--
-- TOC entry 4060 (class 2606 OID 25534)
-- Name: tipos_habitacion unique_tipo_hotel; Type: CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.tipos_habitacion
    ADD CONSTRAINT unique_tipo_hotel UNIQUE (hotel_id, nombre);


--
-- TOC entry 4078 (class 2620 OID 25682)
-- Name: reservaciones tg_bitacora_reservaciones; Type: TRIGGER; Schema: public; Owner: nechavarria
--

CREATE TRIGGER tg_bitacora_reservaciones AFTER INSERT OR DELETE OR UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.tr_bitacora_reservaciones();


--
-- TOC entry 4076 (class 2620 OID 25613)
-- Name: pagos tr_bitacora_pagos; Type: TRIGGER; Schema: public; Owner: nechavarria
--

CREATE TRIGGER tr_bitacora_pagos AFTER INSERT OR DELETE OR UPDATE ON public.pagos FOR EACH ROW EXECUTE FUNCTION public.bitacora_pagos_trigger();


--
-- TOC entry 4079 (class 2620 OID 25615)
-- Name: reservaciones tr_cancelacion_reservacion; Type: TRIGGER; Schema: public; Owner: nechavarria
--

CREATE TRIGGER tr_cancelacion_reservacion AFTER UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.cancelacion_reservacion_trigger();


--
-- TOC entry 4077 (class 2620 OID 25616)
-- Name: pagos tr_pago_registrado; Type: TRIGGER; Schema: public; Owner: nechavarria
--

CREATE TRIGGER tr_pago_registrado AFTER UPDATE ON public.pagos FOR EACH ROW EXECUTE FUNCTION public.pago_registrado_trigger();


--
-- TOC entry 4063 (class 2606 OID 25542)
-- Name: facturas facturas_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4064 (class 2606 OID 25535)
-- Name: fidelizacion_clientes fidelizacion_clientes_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4065 (class 2606 OID 25547)
-- Name: fidelizacion_clientes fidelizacion_clientes_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4066 (class 2606 OID 25552)
-- Name: habitaciones habitaciones_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT habitaciones_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4067 (class 2606 OID 25557)
-- Name: historico_estadias historico_estadias_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4068 (class 2606 OID 25562)
-- Name: historico_estadias historico_estadias_habitacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_habitacion_id_fkey FOREIGN KEY (habitacion_id) REFERENCES public.habitaciones(habitacion_id);


--
-- TOC entry 4069 (class 2606 OID 25567)
-- Name: historico_estadias historico_estadias_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4070 (class 2606 OID 25572)
-- Name: politicas_temporada politicas_temporada_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.politicas_temporada
    ADD CONSTRAINT politicas_temporada_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4071 (class 2606 OID 25577)
-- Name: reservacion_habitaciones reservacion_habitaciones_habitacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservacion_habitaciones
    ADD CONSTRAINT reservacion_habitaciones_habitacion_id_fkey FOREIGN KEY (habitacion_id) REFERENCES public.habitaciones(habitacion_id);


--
-- TOC entry 4072 (class 2606 OID 25582)
-- Name: reservaciones reservaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4073 (class 2606 OID 25587)
-- Name: reservaciones reservaciones_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4074 (class 2606 OID 25592)
-- Name: servicios_hotel servicios_hotel_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.servicios_hotel
    ADD CONSTRAINT servicios_hotel_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4075 (class 2606 OID 25597)
-- Name: tipos_habitacion tipos_habitacion_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nechavarria
--

ALTER TABLE ONLY public.tipos_habitacion
    ADD CONSTRAINT tipos_habitacion_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4260 (class 0 OID 0)
-- Dependencies: 256
-- Name: FUNCTION pg_replication_origin_advance(text, pg_lsn); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_advance(text, pg_lsn) TO azure_pg_admin;


--
-- TOC entry 4261 (class 0 OID 0)
-- Dependencies: 257
-- Name: FUNCTION pg_replication_origin_create(text); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_create(text) TO azure_pg_admin;


--
-- TOC entry 4262 (class 0 OID 0)
-- Dependencies: 258
-- Name: FUNCTION pg_replication_origin_drop(text); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_drop(text) TO azure_pg_admin;


--
-- TOC entry 4263 (class 0 OID 0)
-- Dependencies: 247
-- Name: FUNCTION pg_replication_origin_oid(text); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_oid(text) TO azure_pg_admin;


--
-- TOC entry 4264 (class 0 OID 0)
-- Dependencies: 248
-- Name: FUNCTION pg_replication_origin_progress(text, boolean); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_progress(text, boolean) TO azure_pg_admin;


--
-- TOC entry 4265 (class 0 OID 0)
-- Dependencies: 259
-- Name: FUNCTION pg_replication_origin_session_is_setup(); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_session_is_setup() TO azure_pg_admin;


--
-- TOC entry 4266 (class 0 OID 0)
-- Dependencies: 260
-- Name: FUNCTION pg_replication_origin_session_progress(boolean); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_session_progress(boolean) TO azure_pg_admin;


--
-- TOC entry 4267 (class 0 OID 0)
-- Dependencies: 261
-- Name: FUNCTION pg_replication_origin_session_reset(); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_session_reset() TO azure_pg_admin;


--
-- TOC entry 4268 (class 0 OID 0)
-- Dependencies: 262
-- Name: FUNCTION pg_replication_origin_session_setup(text); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_session_setup(text) TO azure_pg_admin;


--
-- TOC entry 4269 (class 0 OID 0)
-- Dependencies: 265
-- Name: FUNCTION pg_replication_origin_xact_reset(); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_xact_reset() TO azure_pg_admin;


--
-- TOC entry 4270 (class 0 OID 0)
-- Dependencies: 263
-- Name: FUNCTION pg_replication_origin_xact_setup(pg_lsn, timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_replication_origin_xact_setup(pg_lsn, timestamp with time zone) TO azure_pg_admin;


--
-- TOC entry 4271 (class 0 OID 0)
-- Dependencies: 264
-- Name: FUNCTION pg_show_replication_origin_status(OUT local_id oid, OUT external_id text, OUT remote_lsn pg_lsn, OUT local_lsn pg_lsn); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_show_replication_origin_status(OUT local_id oid, OUT external_id text, OUT remote_lsn pg_lsn, OUT local_lsn pg_lsn) TO azure_pg_admin;


--
-- TOC entry 4272 (class 0 OID 0)
-- Dependencies: 251
-- Name: FUNCTION pg_stat_reset(); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_stat_reset() TO azure_pg_admin;


--
-- TOC entry 4273 (class 0 OID 0)
-- Dependencies: 249
-- Name: FUNCTION pg_stat_reset_shared(target text); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_stat_reset_shared(target text) TO azure_pg_admin;


--
-- TOC entry 4274 (class 0 OID 0)
-- Dependencies: 253
-- Name: FUNCTION pg_stat_reset_single_function_counters(oid); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_stat_reset_single_function_counters(oid) TO azure_pg_admin;


--
-- TOC entry 4275 (class 0 OID 0)
-- Dependencies: 252
-- Name: FUNCTION pg_stat_reset_single_table_counters(oid); Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT ALL ON FUNCTION pg_catalog.pg_stat_reset_single_table_counters(oid) TO azure_pg_admin;


--
-- TOC entry 4276 (class 0 OID 0)
-- Dependencies: 98
-- Name: COLUMN pg_config.name; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(name) ON TABLE pg_catalog.pg_config TO azure_pg_admin;


--
-- TOC entry 4277 (class 0 OID 0)
-- Dependencies: 98
-- Name: COLUMN pg_config.setting; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(setting) ON TABLE pg_catalog.pg_config TO azure_pg_admin;


--
-- TOC entry 4278 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.line_number; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(line_number) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4279 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.type; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(type) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4280 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.database; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(database) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4281 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.user_name; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(user_name) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4282 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.address; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(address) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4283 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.netmask; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(netmask) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4284 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.auth_method; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(auth_method) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4285 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.options; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(options) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4286 (class 0 OID 0)
-- Dependencies: 94
-- Name: COLUMN pg_hba_file_rules.error; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(error) ON TABLE pg_catalog.pg_hba_file_rules TO azure_pg_admin;


--
-- TOC entry 4287 (class 0 OID 0)
-- Dependencies: 145
-- Name: COLUMN pg_replication_origin_status.local_id; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(local_id) ON TABLE pg_catalog.pg_replication_origin_status TO azure_pg_admin;


--
-- TOC entry 4288 (class 0 OID 0)
-- Dependencies: 145
-- Name: COLUMN pg_replication_origin_status.external_id; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(external_id) ON TABLE pg_catalog.pg_replication_origin_status TO azure_pg_admin;


--
-- TOC entry 4289 (class 0 OID 0)
-- Dependencies: 145
-- Name: COLUMN pg_replication_origin_status.remote_lsn; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(remote_lsn) ON TABLE pg_catalog.pg_replication_origin_status TO azure_pg_admin;


--
-- TOC entry 4290 (class 0 OID 0)
-- Dependencies: 145
-- Name: COLUMN pg_replication_origin_status.local_lsn; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(local_lsn) ON TABLE pg_catalog.pg_replication_origin_status TO azure_pg_admin;


--
-- TOC entry 4291 (class 0 OID 0)
-- Dependencies: 99
-- Name: COLUMN pg_shmem_allocations.name; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(name) ON TABLE pg_catalog.pg_shmem_allocations TO azure_pg_admin;


--
-- TOC entry 4292 (class 0 OID 0)
-- Dependencies: 99
-- Name: COLUMN pg_shmem_allocations.off; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(off) ON TABLE pg_catalog.pg_shmem_allocations TO azure_pg_admin;


--
-- TOC entry 4293 (class 0 OID 0)
-- Dependencies: 99
-- Name: COLUMN pg_shmem_allocations.size; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(size) ON TABLE pg_catalog.pg_shmem_allocations TO azure_pg_admin;


--
-- TOC entry 4294 (class 0 OID 0)
-- Dependencies: 99
-- Name: COLUMN pg_shmem_allocations.allocated_size; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(allocated_size) ON TABLE pg_catalog.pg_shmem_allocations TO azure_pg_admin;


--
-- TOC entry 4295 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.starelid; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(starelid) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4296 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staattnum; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staattnum) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4297 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stainherit; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stainherit) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4298 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanullfrac; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanullfrac) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4299 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stawidth; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stawidth) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4300 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stadistinct; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stadistinct) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4301 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stakind1; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stakind1) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4302 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stakind2; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stakind2) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4303 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stakind3; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stakind3) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4304 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stakind4; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stakind4) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4305 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stakind5; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stakind5) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4306 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staop1; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staop1) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4307 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staop2; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staop2) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4308 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staop3; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staop3) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4309 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staop4; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staop4) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4310 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.staop5; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(staop5) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4311 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stacoll1; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stacoll1) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4312 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stacoll2; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stacoll2) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4313 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stacoll3; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stacoll3) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4314 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stacoll4; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stacoll4) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4315 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stacoll5; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stacoll5) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4316 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanumbers1; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanumbers1) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4317 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanumbers2; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanumbers2) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4318 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanumbers3; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanumbers3) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4319 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanumbers4; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanumbers4) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4320 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stanumbers5; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stanumbers5) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4321 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stavalues1; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stavalues1) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4322 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stavalues2; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stavalues2) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4323 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stavalues3; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stavalues3) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4324 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stavalues4; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stavalues4) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4325 (class 0 OID 0)
-- Dependencies: 39
-- Name: COLUMN pg_statistic.stavalues5; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(stavalues5) ON TABLE pg_catalog.pg_statistic TO azure_pg_admin;


--
-- TOC entry 4326 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.oid; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(oid) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4327 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subdbid; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subdbid) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4328 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subname; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subname) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4329 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subowner; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subowner) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4330 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subenabled; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subenabled) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4331 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subconninfo; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subconninfo) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4332 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subslotname; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subslotname) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4333 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subsynccommit; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subsynccommit) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


--
-- TOC entry 4334 (class 0 OID 0)
-- Dependencies: 64
-- Name: COLUMN pg_subscription.subpublications; Type: ACL; Schema: pg_catalog; Owner: azuresu
--

GRANT SELECT(subpublications) ON TABLE pg_catalog.pg_subscription TO azure_pg_admin;


-- Completed on 2025-06-29 09:52:17

--
-- PostgreSQL database dump complete
--

