--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.2

-- Started on 2025-06-05 16:26:46

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
-- TOC entry 266 (class 1255 OID 27436)
-- Name: actualizar_estado_pago(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.actualizar_estado_pago(p_pago_id integer, p_estado character varying, p_usuario character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Validar estado
    IF p_estado NOT IN ('pendiente', 'completado', 'reembolsado', 'fallido') THEN
        RAISE EXCEPTION 'Estado de pago no v lido';
    END IF;
    
    -- Actualizar estado del pago (el trigger manejar  la actualizaci¢n de la reserva)
    UPDATE pagos
    SET estado = p_estado
    WHERE pago_id = p_pago_id;
    
    -- Registrar en bit cora
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


ALTER FUNCTION public.actualizar_estado_pago(p_pago_id integer, p_estado character varying, p_usuario character varying) OWNER TO postgres;

--
-- TOC entry 249 (class 1255 OID 27439)
-- Name: bitacora_pagos_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
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
            'Nuevo pago registrado. Monto: ' || NEW.monto || ', M‚todo: ' || NEW.metodo_pago,
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


ALTER FUNCTION public.bitacora_pagos_trigger() OWNER TO postgres;

--
-- TOC entry 267 (class 1255 OID 27437)
-- Name: bitacora_reservaciones_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bitacora_reservaciones_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_accion VARCHAR;
    v_detalles TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_accion := 'CREACION';
        v_detalles := 'Nueva reserva creada. Estado: ' || NEW.estado;
    ELSIF TG_OP = 'UPDATE' THEN
        v_accion := 'ACTUALIZACION';
        v_detalles := 'Estado cambiado de ' || OLD.estado || ' a ' || NEW.estado;
        
        -- Detalles adicionales para cambios espec¡ficos
        IF OLD.fecha_entrada != NEW.fecha_entrada OR OLD.fecha_salida != NEW.fecha_salida THEN
            v_detalles := v_detalles || '. Fechas modificadas.';
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        v_accion := 'ELIMINACION';
        v_detalles := 'Reserva eliminada';
    END IF;
    
    PERFORM registrar_bitacora(
        CURRENT_USER, 
        v_accion, 
        'reservaciones', 
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


ALTER FUNCTION public.bitacora_reservaciones_trigger() OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 27428)
-- Name: cancelacion_reservacion_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
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
        -- Calcular d¡as restantes hasta la fecha de entrada
        v_dias_restantes := NEW.fecha_entrada - CURRENT_DATE;
        
        -- Registrar en bit cora
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'CANCELACION', 
            'reservaciones', 
            NEW.reservacion_id, 
            'Reserva cancelada. D¡as restantes: ' || v_dias_restantes,
            inet_client_addr()::TEXT
        );
        
        -- Enviar alerta si es cancelaci¢n de £ltima hora (menos de 3 d¡as)
        IF v_dias_restantes < 3 THEN
            -- Obtener informaci¢n para la alerta
            SELECT nombre INTO v_hotel_nombre FROM hoteles WHERE hotel_id = NEW.hotel_id;
            SELECT nombre INTO v_cliente_nombre FROM clientes WHERE cliente_id = NEW.cliente_id;
            
            -- Registrar alerta en bit cora
            PERFORM registrar_bitacora(
                CURRENT_USER, 
                'ALERTA', 
                'reservaciones', 
                NEW.reservacion_id, 
                'ALERTA: Cancelaci¢n de £ltima hora. Cliente: ' || v_cliente_nombre || ', Hotel: ' || v_hotel_nombre,
                inet_client_addr()::TEXT
            );
            
            -- Aqu¡ podr¡as agregar l¢gica para enviar email/notificaci¢n
            RAISE NOTICE 'ALERTA: Cancelaci¢n de £ltima hora. Reservaci¢n ID: %, Cliente: %, Hotel: %', 
                         NEW.reservacion_id, v_cliente_nombre, v_hotel_nombre;
        END IF;
        
        -- Liberar habitaciones asociadas
        UPDATE habitaciones h
        SET estado = 'disponible'
        FROM reservacion_habitaciones rh
        WHERE rh.habitacion_id = h.habitacion_id
        AND rh.reservacion_id = NEW.reservacion_id;
        
        -- Registrar liberaci¢n en bit cora
        PERFORM registrar_bitacora(
            CURRENT_USER, 
            'ACTUALIZACION', 
            'habitaciones', 
            NEW.reservacion_id, 
            'Habitaciones liberadas por cancelaci¢n de reserva',
            inet_client_addr()::TEXT
        );
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.cancelacion_reservacion_trigger() OWNER TO postgres;

--
-- TOC entry 265 (class 1255 OID 27435)
-- Name: cancelar_reservacion(integer, character varying, text); Type: FUNCTION; Schema: public; Owner: postgres
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
        RAISE EXCEPTION 'Reservaci¢n no encontrada';
    END IF;
    
    IF v_estado_actual = 'cancelada' THEN
        RAISE NOTICE 'La reservaci¢n ya est  cancelada';
        RETURN;
    END IF;
    
    -- Actualizar estado a cancelada
    UPDATE reservaciones 
    SET estado = 'cancelada'
    WHERE reservacion_id = p_reservacion_id;
    
    -- Registrar en bit cora (el trigger manejar  la liberaci¢n de habitaciones)
    PERFORM registrar_bitacora(
        p_usuario, 
        'CANCELACION', 
        'reservaciones', 
        p_reservacion_id, 
        'Reserva cancelada. Raz¢n: ' || COALESCE(p_razon, 'No especificada'),
        inet_client_addr()::TEXT
    );
END;
$$;


ALTER FUNCTION public.cancelar_reservacion(p_reservacion_id integer, p_usuario character varying, p_razon text) OWNER TO postgres;

--
-- TOC entry 264 (class 1255 OID 27433)
-- Name: crear_reservacion(integer, integer, date, date, integer, integer, character varying, text, character varying, character varying, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
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
        RAISE EXCEPTION 'Debe haber al menos un adulto en la reservaci¢n';
    END IF;
    
    -- Verificar disponibilidad para cada tipo de habitaci¢n solicitada
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_tipos_habitaciones) LOOP
        -- Verificar que exista el tipo de habitaci¢n en el hotel
        PERFORM 1 FROM tipos_habitacion 
        WHERE tipo_id = (v_item->>'tipo_id')::INTEGER AND hotel_id = p_hotel_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El tipo de habitaci¢n % no existe en este hotel', (v_item->>'tipo_id');
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
    
    -- Generar c¢digo de reserva £nico
    v_codigo_reserva := 'RES-' || p_hotel_id || '-' || 
                        EXTRACT(YEAR FROM CURRENT_DATE) || '-' || 
                        LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');
    
    -- Crear la reservaci¢n principal
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
    
    -- Asignar habitaciones espec¡ficas
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
            -- Asignar habitaci¢n a la reservaci¢n
            INSERT INTO reservacion_habitaciones (
                reservacion_id,
                habitacion_id,
                tarifa_aplicada,
                notas
            ) VALUES (
                v_reservacion_id,
                v_habitacion.habitacion_id,
                v_tarifa,
                'Asignaci¢n inicial'
            );
            
            -- Marcar habitaci¢n como ocupada
            UPDATE habitaciones 
            SET estado = 'ocupada' 
            WHERE habitacion_id = v_habitacion.habitacion_id;
        END LOOP;
    END LOOP;
    
    -- Registrar en bit cora
    PERFORM registrar_bitacora(
        p_usuario,
        'CREACION',
        'reservaciones',
        v_reservacion_id,
        'Reserva creada con c¢digo ' || v_codigo_reserva,
        p_ip_origen
    );
    
    RETURN v_reservacion_id;
END;
$$;


ALTER FUNCTION public.crear_reservacion(p_hotel_id integer, p_cliente_id integer, p_fecha_entrada date, p_fecha_salida date, p_adultos integer, p_ninos integer, p_tipo_reserva character varying, p_solicitudes_especiales text, p_usuario character varying, p_ip_origen character varying, p_tipos_habitaciones jsonb) OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 27430)
-- Name: pago_registrado_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.pago_registrado_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Solo actuar cuando el pago se marca como completado
    IF NEW.estado = 'completado' AND OLD.estado != 'completado' THEN
        -- Actualizar estado de la reservaci¢n a 'confirmada'
        UPDATE reservaciones
        SET estado = 'confirmada'
        WHERE reservacion_id = NEW.reservacion_id;
        
        -- Registrar en bit cora
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


ALTER FUNCTION public.pago_registrado_trigger() OWNER TO postgres;

--
-- TOC entry 251 (class 1255 OID 27442)
-- Name: registrar_bitacora(name, character varying, character varying, integer, text, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_bitacora(p_usuario name, p_accion character varying, p_tabla character varying, p_registro_id integer, p_detalles text, p_ip character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO bitacora_reservaciones (usuario, accion, tabla_afectada, registro_id, detalles, ip_origen)
    VALUES (p_usuario, p_accion, p_tabla, p_registro_id, p_detalles, p_ip);
END;
$$;


ALTER FUNCTION public.registrar_bitacora(p_usuario name, p_accion character varying, p_tabla character varying, p_registro_id integer, p_detalles text, p_ip character varying) OWNER TO postgres;

--
-- TOC entry 250 (class 1255 OID 27427)
-- Name: registrar_bitacora(character varying, character varying, character varying, integer, text, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_bitacora(p_usuario character varying, p_accion character varying, p_tabla character varying, p_registro_id integer, p_detalles text, p_ip character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO bitacora_reservaciones (usuario, accion, tabla_afectada, registro_id, detalles, ip_origen)
    VALUES (p_usuario, p_accion, p_tabla, p_registro_id, p_detalles, p_ip);
END;
$$;


ALTER FUNCTION public.registrar_bitacora(p_usuario character varying, p_accion character varying, p_tabla character varying, p_registro_id integer, p_detalles text, p_ip character varying) OWNER TO postgres;

--
-- TOC entry 263 (class 1255 OID 27432)
-- Name: verificar_disponibilidad(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
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


ALTER FUNCTION public.verificar_disponibilidad(p_hotel_id integer, p_tipo_id integer, p_fecha_entrada date, p_fecha_salida date) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 246 (class 1259 OID 27418)
-- Name: bitacora_reservaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bitacora_reservaciones (
    bitacora_id integer NOT NULL,
    fecha_hora timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    usuario character varying(50),
    accion character varying(20) NOT NULL,
    tabla_afectada character varying(30) NOT NULL,
    registro_id integer NOT NULL,
    detalles text,
    ip_origen character varying(50)
);


ALTER TABLE public.bitacora_reservaciones OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 27417)
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bitacora_reservaciones_bitacora_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bitacora_reservaciones_bitacora_id_seq OWNER TO postgres;

--
-- TOC entry 5068 (class 0 OID 0)
-- Dependencies: 245
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bitacora_reservaciones_bitacora_id_seq OWNED BY public.bitacora_reservaciones.bitacora_id;


--
-- TOC entry 220 (class 1259 OID 27156)
-- Name: clientes; Type: TABLE; Schema: public; Owner: postgres
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
    preferencias text,
    alergias text
);


ALTER TABLE public.clientes OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 27155)
-- Name: clientes_cliente_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clientes_cliente_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clientes_cliente_id_seq OWNER TO postgres;

--
-- TOC entry 5069 (class 0 OID 0)
-- Dependencies: 219
-- Name: clientes_cliente_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clientes_cliente_id_seq OWNED BY public.clientes.cliente_id;


--
-- TOC entry 242 (class 1259 OID 27367)
-- Name: facturas; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.facturas OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 27366)
-- Name: facturas_factura_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.facturas_factura_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.facturas_factura_id_seq OWNER TO postgres;

--
-- TOC entry 5070 (class 0 OID 0)
-- Dependencies: 241
-- Name: facturas_factura_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.facturas_factura_id_seq OWNED BY public.facturas.factura_id;


--
-- TOC entry 222 (class 1259 OID 27171)
-- Name: fidelizacion_clientes; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.fidelizacion_clientes OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 27170)
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq OWNER TO postgres;

--
-- TOC entry 5071 (class 0 OID 0)
-- Dependencies: 221
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.fidelizacion_clientes_fidelizacion_id_seq OWNED BY public.fidelizacion_clientes.fidelizacion_id;


--
-- TOC entry 226 (class 1259 OID 27210)
-- Name: habitaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.habitaciones (
    habitacion_id integer NOT NULL,
    hotel_id integer,
    numero character varying(10) NOT NULL,
    tipo_id integer,
    piso integer NOT NULL,
    caracteristicas_especiales text,
    estado character varying(20) NOT NULL,
    notas text,
    CONSTRAINT habitaciones_estado_check CHECK (((estado)::text = ANY ((ARRAY['disponible'::character varying, 'ocupada'::character varying, 'mantenimiento'::character varying, 'limpieza'::character varying])::text[])))
);


ALTER TABLE public.habitaciones OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 27209)
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.habitaciones_habitacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.habitaciones_habitacion_id_seq OWNER TO postgres;

--
-- TOC entry 5072 (class 0 OID 0)
-- Dependencies: 225
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.habitaciones_habitacion_id_seq OWNED BY public.habitaciones.habitacion_id;


--
-- TOC entry 244 (class 1259 OID 27388)
-- Name: historico_estadias; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.historico_estadias OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 27387)
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.historico_estadias_historico_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historico_estadias_historico_id_seq OWNER TO postgres;

--
-- TOC entry 5073 (class 0 OID 0)
-- Dependencies: 243
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.historico_estadias_historico_id_seq OWNED BY public.historico_estadias.historico_id;


--
-- TOC entry 218 (class 1259 OID 27145)
-- Name: hoteles; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.hoteles OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 27144)
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.hoteles_hotel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.hoteles_hotel_id_seq OWNER TO postgres;

--
-- TOC entry 5074 (class 0 OID 0)
-- Dependencies: 217
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.hoteles_hotel_id_seq OWNED BY public.hoteles.hotel_id;


--
-- TOC entry 240 (class 1259 OID 27351)
-- Name: pagos; Type: TABLE; Schema: public; Owner: postgres
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
    CONSTRAINT pagos_estado_check CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'completado'::character varying, 'reembolsado'::character varying, 'fallido'::character varying])::text[])))
);


ALTER TABLE public.pagos OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 27350)
-- Name: pagos_pago_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pagos_pago_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pagos_pago_id_seq OWNER TO postgres;

--
-- TOC entry 5075 (class 0 OID 0)
-- Dependencies: 239
-- Name: pagos_pago_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pagos_pago_id_seq OWNED BY public.pagos.pago_id;


--
-- TOC entry 228 (class 1259 OID 27232)
-- Name: politicas_temporada; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.politicas_temporada OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 27231)
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.politicas_temporada_politica_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.politicas_temporada_politica_id_seq OWNER TO postgres;

--
-- TOC entry 5076 (class 0 OID 0)
-- Dependencies: 227
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.politicas_temporada_politica_id_seq OWNED BY public.politicas_temporada.politica_id;


--
-- TOC entry 234 (class 1259 OID 27296)
-- Name: reservacion_habitaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservacion_habitaciones (
    detalle_id integer NOT NULL,
    reservacion_id integer,
    habitacion_id integer,
    tarifa_aplicada numeric(10,2) NOT NULL,
    notas text
);


ALTER TABLE public.reservacion_habitaciones OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 27295)
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reservacion_habitaciones_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservacion_habitaciones_detalle_id_seq OWNER TO postgres;

--
-- TOC entry 5077 (class 0 OID 0)
-- Dependencies: 233
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reservacion_habitaciones_detalle_id_seq OWNED BY public.reservacion_habitaciones.detalle_id;


--
-- TOC entry 236 (class 1259 OID 27317)
-- Name: reservacion_servicios; Type: TABLE; Schema: public; Owner: postgres
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
    CONSTRAINT reservacion_servicios_estado_check CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'completado'::character varying, 'cancelado'::character varying])::text[])))
);


ALTER TABLE public.reservacion_servicios OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 27316)
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq OWNER TO postgres;

--
-- TOC entry 5078 (class 0 OID 0)
-- Dependencies: 235
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reservacion_servicios_detalle_servicio_id_seq OWNED BY public.reservacion_servicios.detalle_servicio_id;


--
-- TOC entry 232 (class 1259 OID 27270)
-- Name: reservaciones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservaciones (
    reservacion_id integer NOT NULL,
    hotel_id integer,
    cliente_id integer,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    fecha_entrada date NOT NULL,
    fecha_salida date NOT NULL,
    adultos integer NOT NULL,
    ninos integer DEFAULT 0,
    estado character varying(20) NOT NULL,
    tipo_reserva character varying(20) NOT NULL,
    solicitudes_especiales text,
    codigo_reserva character varying(20),
    CONSTRAINT fechas_validas CHECK ((fecha_salida > fecha_entrada)),
    CONSTRAINT reservaciones_estado_check CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'confirmada'::character varying, 'cancelada'::character varying, 'completada'::character varying, 'no-show'::character varying])::text[]))),
    CONSTRAINT reservaciones_tipo_reserva_check CHECK (((tipo_reserva)::text = ANY ((ARRAY['individual'::character varying, 'grupo'::character varying, 'corporativa'::character varying])::text[])))
);


ALTER TABLE public.reservaciones OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 27269)
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.reservaciones_reservacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.reservaciones_reservacion_id_seq OWNER TO postgres;

--
-- TOC entry 5079 (class 0 OID 0)
-- Dependencies: 231
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.reservaciones_reservacion_id_seq OWNED BY public.reservaciones.reservacion_id;


--
-- TOC entry 238 (class 1259 OID 27334)
-- Name: servicios_hotel; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.servicios_hotel OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 27333)
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.servicios_hotel_servicio_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.servicios_hotel_servicio_id_seq OWNER TO postgres;

--
-- TOC entry 5080 (class 0 OID 0)
-- Dependencies: 237
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.servicios_hotel_servicio_id_seq OWNED BY public.servicios_hotel.servicio_id;


--
-- TOC entry 230 (class 1259 OID 27249)
-- Name: tarifas_temporada; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tarifas_temporada (
    tarifa_id integer NOT NULL,
    politica_id integer,
    tipo_id integer,
    precio numeric(10,2) NOT NULL,
    descripcion text
);


ALTER TABLE public.tarifas_temporada OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 27248)
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tarifas_temporada_tarifa_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tarifas_temporada_tarifa_id_seq OWNER TO postgres;

--
-- TOC entry 5081 (class 0 OID 0)
-- Dependencies: 229
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tarifas_temporada_tarifa_id_seq OWNED BY public.tarifas_temporada.tarifa_id;


--
-- TOC entry 224 (class 1259 OID 27194)
-- Name: tipos_habitacion; Type: TABLE; Schema: public; Owner: postgres
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


ALTER TABLE public.tipos_habitacion OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 27193)
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipos_habitacion_tipo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipos_habitacion_tipo_id_seq OWNER TO postgres;

--
-- TOC entry 5082 (class 0 OID 0)
-- Dependencies: 223
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipos_habitacion_tipo_id_seq OWNED BY public.tipos_habitacion.tipo_id;


--
-- TOC entry 4800 (class 2604 OID 27421)
-- Name: bitacora_reservaciones bitacora_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bitacora_reservaciones ALTER COLUMN bitacora_id SET DEFAULT nextval('public.bitacora_reservaciones_bitacora_id_seq'::regclass);


--
-- TOC entry 4777 (class 2604 OID 27159)
-- Name: clientes cliente_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes ALTER COLUMN cliente_id SET DEFAULT nextval('public.clientes_cliente_id_seq'::regclass);


--
-- TOC entry 4798 (class 2604 OID 27370)
-- Name: facturas factura_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas ALTER COLUMN factura_id SET DEFAULT nextval('public.facturas_factura_id_seq'::regclass);


--
-- TOC entry 4780 (class 2604 OID 27174)
-- Name: fidelizacion_clientes fidelizacion_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fidelizacion_clientes ALTER COLUMN fidelizacion_id SET DEFAULT nextval('public.fidelizacion_clientes_fidelizacion_id_seq'::regclass);


--
-- TOC entry 4784 (class 2604 OID 27213)
-- Name: habitaciones habitacion_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitaciones ALTER COLUMN habitacion_id SET DEFAULT nextval('public.habitaciones_habitacion_id_seq'::regclass);


--
-- TOC entry 4799 (class 2604 OID 27391)
-- Name: historico_estadias historico_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias ALTER COLUMN historico_id SET DEFAULT nextval('public.historico_estadias_historico_id_seq'::regclass);


--
-- TOC entry 4775 (class 2604 OID 27148)
-- Name: hoteles hotel_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hoteles ALTER COLUMN hotel_id SET DEFAULT nextval('public.hoteles_hotel_id_seq'::regclass);


--
-- TOC entry 4796 (class 2604 OID 27354)
-- Name: pagos pago_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos ALTER COLUMN pago_id SET DEFAULT nextval('public.pagos_pago_id_seq'::regclass);


--
-- TOC entry 4785 (class 2604 OID 27235)
-- Name: politicas_temporada politica_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.politicas_temporada ALTER COLUMN politica_id SET DEFAULT nextval('public.politicas_temporada_politica_id_seq'::regclass);


--
-- TOC entry 4790 (class 2604 OID 27299)
-- Name: reservacion_habitaciones detalle_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_habitaciones ALTER COLUMN detalle_id SET DEFAULT nextval('public.reservacion_habitaciones_detalle_id_seq'::regclass);


--
-- TOC entry 4791 (class 2604 OID 27320)
-- Name: reservacion_servicios detalle_servicio_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_servicios ALTER COLUMN detalle_servicio_id SET DEFAULT nextval('public.reservacion_servicios_detalle_servicio_id_seq'::regclass);


--
-- TOC entry 4787 (class 2604 OID 27273)
-- Name: reservaciones reservacion_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones ALTER COLUMN reservacion_id SET DEFAULT nextval('public.reservaciones_reservacion_id_seq'::regclass);


--
-- TOC entry 4794 (class 2604 OID 27337)
-- Name: servicios_hotel servicio_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicios_hotel ALTER COLUMN servicio_id SET DEFAULT nextval('public.servicios_hotel_servicio_id_seq'::regclass);


--
-- TOC entry 4786 (class 2604 OID 27252)
-- Name: tarifas_temporada tarifa_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifas_temporada ALTER COLUMN tarifa_id SET DEFAULT nextval('public.tarifas_temporada_tarifa_id_seq'::regclass);


--
-- TOC entry 4783 (class 2604 OID 27197)
-- Name: tipos_habitacion tipo_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_habitacion ALTER COLUMN tipo_id SET DEFAULT nextval('public.tipos_habitacion_tipo_id_seq'::regclass);


--
-- TOC entry 5062 (class 0 OID 27418)
-- Dependencies: 246
-- Data for Name: bitacora_reservaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bitacora_reservaciones (bitacora_id, fecha_hora, usuario, accion, tabla_afectada, registro_id, detalles, ip_origen) FROM stdin;
1	2025-05-20 22:23:10.984702	postgres	CREACION	reservaciones	4	Nueva reserva creada. Estado: confirmada	::1/128
2	2025-05-20 22:23:10.984702	127.0.0.1	CREACION	reservaciones	4	Reserva creada con c¢digo RES-1-2025-9739	[{"tipo_id": 1, "cantidad": 1}]
3	2025-05-20 22:25:49.649673	postgres	ACTUALIZACION	reservaciones	4	Estado cambiado de confirmada a cancelada	::1/128
4	2025-05-20 22:25:49.649673	postgres	CANCELACION	reservaciones	4	Reserva cancelada. D¡as restantes: 209	::1/128
5	2025-05-20 22:25:49.649673	postgres	ACTUALIZACION	habitaciones	4	Habitaciones liberadas por cancelaci¢n de reserva	::1/128
6	2025-05-20 22:25:49.649673	admin	CANCELACION	reservaciones	4	Reserva cancelada. Raz¢n: Cambio de planes	::1/128
7	2025-05-20 22:29:42.72008	postgres	CREACION	reservaciones	5	Nueva reserva creada. Estado: confirmada	::1/128
8	2025-05-20 22:29:42.72008	127.0.3.1	CREACION	reservaciones	5	Reserva creada con c¢digo RES-1-2025-7587	[{"tipo_id": 1, "cantidad": 1}]
9	2025-05-20 22:30:34.031821	postgres	CREACION	pagos	1	Nuevo pago registrado. Monto: 100.00, M‚todo: Tarjeta	::1/128
10	2025-05-20 22:33:33.331128	admin	ACTUALIZACION	pagos	5	Estado de pago actualizado a: completado	::1/128
\.


--
-- TOC entry 5036 (class 0 OID 27156)
-- Dependencies: 220
-- Data for Name: clientes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clientes (cliente_id, nombre, documento_identidad, tipo_documento, nacionalidad, telefono, email, fecha_registro, activo, preferencias, alergias) FROM stdin;
1	Carlos P‚rez	12345678	DNI	Costarricense	8888-9999	carlos@example.com	2025-05-20 22:14:34.702087	t	Cama King, Piso alto	Ninguna
\.


--
-- TOC entry 5058 (class 0 OID 27367)
-- Dependencies: 242
-- Data for Name: facturas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.facturas (factura_id, pago_id, hotel_id, numero_factura, fecha_emision, subtotal, impuestos, total, datos_cliente, detalles) FROM stdin;
\.


--
-- TOC entry 5038 (class 0 OID 27171)
-- Dependencies: 222
-- Data for Name: fidelizacion_clientes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.fidelizacion_clientes (fidelizacion_id, cliente_id, hotel_id, puntos_acumulados, nivel_membresia, beneficios, fecha_actualizacion) FROM stdin;
1	1	1	500	Oro	Check-out tard¡o, upgrades gratuitos	2025-05-20 22:14:34.722928
\.


--
-- TOC entry 5042 (class 0 OID 27210)
-- Dependencies: 226
-- Data for Name: habitaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.habitaciones (habitacion_id, hotel_id, numero, tipo_id, piso, caracteristicas_especiales, estado, notas) FROM stdin;
2	1	102	1	1	\N	disponible	\N
3	1	201	2	2	Balc¢n	disponible	\N
1	1	101	1	1	Vista al jard¡n	ocupada	\N
\.


--
-- TOC entry 5060 (class 0 OID 27388)
-- Dependencies: 244
-- Data for Name: historico_estadias; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.historico_estadias (historico_id, hotel_id, cliente_id, reservacion_id, fecha_entrada, fecha_salida, habitacion_id, comentarios, calificacion, preferencias_registradas) FROM stdin;
\.


--
-- TOC entry 5034 (class 0 OID 27145)
-- Dependencies: 218
-- Data for Name: hoteles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.hoteles (hotel_id, nombre, direccion, ciudad, pais, telefono, email, estrellas, activo, fecha_apertura, descripcion) FROM stdin;
1	Hotel Central	Av. Principal 123	San Jos‚	Costa Rica	2222-1111	central@hotel.com	4	t	2020-01-01	Hotel de lujo en el centro
\.


--
-- TOC entry 5056 (class 0 OID 27351)
-- Dependencies: 240
-- Data for Name: pagos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pagos (pago_id, reservacion_id, monto, metodo_pago, fecha_pago, estado, referencia, descripcion) FROM stdin;
1	5	100.00	Tarjeta	2025-05-20 22:30:34.031821	pendiente	\N	\N
\.


--
-- TOC entry 5044 (class 0 OID 27232)
-- Dependencies: 228
-- Data for Name: politicas_temporada; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.politicas_temporada (politica_id, hotel_id, nombre, fecha_inicio, fecha_fin, descripcion, reglas) FROM stdin;
1	1	Temporada Alta	2025-12-01	2026-01-31	Alt¡sima demanda	Reservas no reembolsables
\.


--
-- TOC entry 5050 (class 0 OID 27296)
-- Dependencies: 234
-- Data for Name: reservacion_habitaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservacion_habitaciones (detalle_id, reservacion_id, habitacion_id, tarifa_aplicada, notas) FROM stdin;
1	4	1	100.00	Asignaci¢n inicial
2	5	1	100.00	Asignaci¢n inicial
\.


--
-- TOC entry 5052 (class 0 OID 27317)
-- Dependencies: 236
-- Data for Name: reservacion_servicios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservacion_servicios (detalle_servicio_id, reservacion_id, servicio_id, tipo_servicio, descripcion, fecha_servicio, cantidad, precio_unitario, notas, estado) FROM stdin;
\.


--
-- TOC entry 5048 (class 0 OID 27270)
-- Dependencies: 232
-- Data for Name: reservaciones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservaciones (reservacion_id, hotel_id, cliente_id, fecha_creacion, fecha_entrada, fecha_salida, adultos, ninos, estado, tipo_reserva, solicitudes_especiales, codigo_reserva) FROM stdin;
4	1	1	2025-05-20 22:23:10.984702	2025-12-15	2025-12-20	2	0	cancelada	individual	Necesita cuna	RES-1-2025-9739
5	1	1	2025-05-20 22:29:42.72008	2025-12-13	2025-12-23	2	1	confirmada	grupo	Necesita cuna	RES-1-2025-7587
\.


--
-- TOC entry 5054 (class 0 OID 27334)
-- Dependencies: 238
-- Data for Name: servicios_hotel; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.servicios_hotel (servicio_id, hotel_id, nombre, descripcion, precio_base, categoria, horario_disponibilidad, activo) FROM stdin;
\.


--
-- TOC entry 5046 (class 0 OID 27249)
-- Dependencies: 230
-- Data for Name: tarifas_temporada; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tarifas_temporada (tarifa_id, politica_id, tipo_id, precio, descripcion) FROM stdin;
1	1	1	100.00	Precio temporada alta - est ndar
2	1	2	200.00	Precio temporada alta - suite
\.


--
-- TOC entry 5040 (class 0 OID 27194)
-- Dependencies: 224
-- Data for Name: tipos_habitacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipos_habitacion (tipo_id, hotel_id, nombre, descripcion, capacidad, tamano, comodidades, precio_base) FROM stdin;
1	1	Est ndar	C¢moda habitaci¢n est ndar	2	20	TV, WiFi, A/C	70.00
2	1	Suite	Suite con sala	4	40	TV, WiFi, A/C, Sala	150.00
\.


--
-- TOC entry 5083 (class 0 OID 0)
-- Dependencies: 245
-- Name: bitacora_reservaciones_bitacora_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bitacora_reservaciones_bitacora_id_seq', 10, true);


--
-- TOC entry 5084 (class 0 OID 0)
-- Dependencies: 219
-- Name: clientes_cliente_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clientes_cliente_id_seq', 1, true);


--
-- TOC entry 5085 (class 0 OID 0)
-- Dependencies: 241
-- Name: facturas_factura_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.facturas_factura_id_seq', 1, false);


--
-- TOC entry 5086 (class 0 OID 0)
-- Dependencies: 221
-- Name: fidelizacion_clientes_fidelizacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.fidelizacion_clientes_fidelizacion_id_seq', 1, true);


--
-- TOC entry 5087 (class 0 OID 0)
-- Dependencies: 225
-- Name: habitaciones_habitacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.habitaciones_habitacion_id_seq', 3, true);


--
-- TOC entry 5088 (class 0 OID 0)
-- Dependencies: 243
-- Name: historico_estadias_historico_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.historico_estadias_historico_id_seq', 1, false);


--
-- TOC entry 5089 (class 0 OID 0)
-- Dependencies: 217
-- Name: hoteles_hotel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.hoteles_hotel_id_seq', 1, true);


--
-- TOC entry 5090 (class 0 OID 0)
-- Dependencies: 239
-- Name: pagos_pago_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pagos_pago_id_seq', 1, true);


--
-- TOC entry 5091 (class 0 OID 0)
-- Dependencies: 227
-- Name: politicas_temporada_politica_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.politicas_temporada_politica_id_seq', 1, true);


--
-- TOC entry 5092 (class 0 OID 0)
-- Dependencies: 233
-- Name: reservacion_habitaciones_detalle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservacion_habitaciones_detalle_id_seq', 2, true);


--
-- TOC entry 5093 (class 0 OID 0)
-- Dependencies: 235
-- Name: reservacion_servicios_detalle_servicio_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservacion_servicios_detalle_servicio_id_seq', 1, false);


--
-- TOC entry 5094 (class 0 OID 0)
-- Dependencies: 231
-- Name: reservaciones_reservacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservaciones_reservacion_id_seq', 5, true);


--
-- TOC entry 5095 (class 0 OID 0)
-- Dependencies: 237
-- Name: servicios_hotel_servicio_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.servicios_hotel_servicio_id_seq', 1, false);


--
-- TOC entry 5096 (class 0 OID 0)
-- Dependencies: 229
-- Name: tarifas_temporada_tarifa_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tarifas_temporada_tarifa_id_seq', 2, true);


--
-- TOC entry 5097 (class 0 OID 0)
-- Dependencies: 223
-- Name: tipos_habitacion_tipo_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipos_habitacion_tipo_id_seq', 2, true);


--
-- TOC entry 4862 (class 2606 OID 27426)
-- Name: bitacora_reservaciones bitacora_reservaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bitacora_reservaciones
    ADD CONSTRAINT bitacora_reservaciones_pkey PRIMARY KEY (bitacora_id);


--
-- TOC entry 4814 (class 2606 OID 27165)
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (cliente_id);


--
-- TOC entry 4856 (class 2606 OID 27376)
-- Name: facturas facturas_numero_factura_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_numero_factura_key UNIQUE (numero_factura);


--
-- TOC entry 4858 (class 2606 OID 27374)
-- Name: facturas facturas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_pkey PRIMARY KEY (factura_id);


--
-- TOC entry 4820 (class 2606 OID 27180)
-- Name: fidelizacion_clientes fidelizacion_clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_pkey PRIMARY KEY (fidelizacion_id);


--
-- TOC entry 4828 (class 2606 OID 27218)
-- Name: habitaciones habitaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT habitaciones_pkey PRIMARY KEY (habitacion_id);


--
-- TOC entry 4860 (class 2606 OID 27396)
-- Name: historico_estadias historico_estadias_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_pkey PRIMARY KEY (historico_id);


--
-- TOC entry 4812 (class 2606 OID 27154)
-- Name: hoteles hoteles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hoteles
    ADD CONSTRAINT hoteles_pkey PRIMARY KEY (hotel_id);


--
-- TOC entry 4854 (class 2606 OID 27360)
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (pago_id);


--
-- TOC entry 4832 (class 2606 OID 27240)
-- Name: politicas_temporada politicas_temporada_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.politicas_temporada
    ADD CONSTRAINT politicas_temporada_pkey PRIMARY KEY (politica_id);


--
-- TOC entry 4844 (class 2606 OID 27303)
-- Name: reservacion_habitaciones reservacion_habitaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_habitaciones
    ADD CONSTRAINT reservacion_habitaciones_pkey PRIMARY KEY (detalle_id);


--
-- TOC entry 4848 (class 2606 OID 27327)
-- Name: reservacion_servicios reservacion_servicios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_servicios
    ADD CONSTRAINT reservacion_servicios_pkey PRIMARY KEY (detalle_servicio_id);


--
-- TOC entry 4840 (class 2606 OID 27284)
-- Name: reservaciones reservaciones_codigo_reserva_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_codigo_reserva_key UNIQUE (codigo_reserva);


--
-- TOC entry 4842 (class 2606 OID 27282)
-- Name: reservaciones reservaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_pkey PRIMARY KEY (reservacion_id);


--
-- TOC entry 4850 (class 2606 OID 27342)
-- Name: servicios_hotel servicios_hotel_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicios_hotel
    ADD CONSTRAINT servicios_hotel_pkey PRIMARY KEY (servicio_id);


--
-- TOC entry 4836 (class 2606 OID 27256)
-- Name: tarifas_temporada tarifas_temporada_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifas_temporada
    ADD CONSTRAINT tarifas_temporada_pkey PRIMARY KEY (tarifa_id);


--
-- TOC entry 4824 (class 2606 OID 27201)
-- Name: tipos_habitacion tipos_habitacion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_habitacion
    ADD CONSTRAINT tipos_habitacion_pkey PRIMARY KEY (tipo_id);


--
-- TOC entry 4822 (class 2606 OID 27182)
-- Name: fidelizacion_clientes unique_cliente_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT unique_cliente_hotel UNIQUE (cliente_id, hotel_id);


--
-- TOC entry 4816 (class 2606 OID 27167)
-- Name: clientes unique_document; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT unique_document UNIQUE (tipo_documento, documento_identidad);


--
-- TOC entry 4818 (class 2606 OID 27169)
-- Name: clientes unique_email; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT unique_email UNIQUE (email);


--
-- TOC entry 4834 (class 2606 OID 27242)
-- Name: politicas_temporada unique_nombre_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.politicas_temporada
    ADD CONSTRAINT unique_nombre_hotel UNIQUE (hotel_id, nombre);


--
-- TOC entry 4830 (class 2606 OID 27220)
-- Name: habitaciones unique_numero_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT unique_numero_hotel UNIQUE (hotel_id, numero);


--
-- TOC entry 4838 (class 2606 OID 27258)
-- Name: tarifas_temporada unique_politica_tipo; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifas_temporada
    ADD CONSTRAINT unique_politica_tipo UNIQUE (politica_id, tipo_id);


--
-- TOC entry 4846 (class 2606 OID 27305)
-- Name: reservacion_habitaciones unique_reservacion_habitacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_habitaciones
    ADD CONSTRAINT unique_reservacion_habitacion UNIQUE (reservacion_id, habitacion_id);


--
-- TOC entry 4852 (class 2606 OID 27344)
-- Name: servicios_hotel unique_servicio_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicios_hotel
    ADD CONSTRAINT unique_servicio_hotel UNIQUE (hotel_id, nombre);


--
-- TOC entry 4826 (class 2606 OID 27203)
-- Name: tipos_habitacion unique_tipo_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_habitacion
    ADD CONSTRAINT unique_tipo_hotel UNIQUE (hotel_id, nombre);


--
-- TOC entry 4886 (class 2620 OID 27440)
-- Name: pagos tr_bitacora_pagos; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_bitacora_pagos AFTER INSERT OR DELETE OR UPDATE ON public.pagos FOR EACH ROW EXECUTE FUNCTION public.bitacora_pagos_trigger();


--
-- TOC entry 4884 (class 2620 OID 27438)
-- Name: reservaciones tr_bitacora_reservaciones; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_bitacora_reservaciones AFTER INSERT OR DELETE OR UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.bitacora_reservaciones_trigger();


--
-- TOC entry 4885 (class 2620 OID 27429)
-- Name: reservaciones tr_cancelacion_reservacion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_cancelacion_reservacion AFTER UPDATE ON public.reservaciones FOR EACH ROW EXECUTE FUNCTION public.cancelacion_reservacion_trigger();


--
-- TOC entry 4887 (class 2620 OID 27431)
-- Name: pagos tr_pago_registrado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_pago_registrado AFTER UPDATE ON public.pagos FOR EACH ROW EXECUTE FUNCTION public.pago_registrado_trigger();


--
-- TOC entry 4878 (class 2606 OID 27382)
-- Name: facturas facturas_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4879 (class 2606 OID 27377)
-- Name: facturas facturas_pago_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_pago_id_fkey FOREIGN KEY (pago_id) REFERENCES public.pagos(pago_id);


--
-- TOC entry 4863 (class 2606 OID 27183)
-- Name: fidelizacion_clientes fidelizacion_clientes_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4864 (class 2606 OID 27188)
-- Name: fidelizacion_clientes fidelizacion_clientes_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fidelizacion_clientes
    ADD CONSTRAINT fidelizacion_clientes_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4866 (class 2606 OID 27221)
-- Name: habitaciones habitaciones_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT habitaciones_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4867 (class 2606 OID 27226)
-- Name: habitaciones habitaciones_tipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitaciones
    ADD CONSTRAINT habitaciones_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES public.tipos_habitacion(tipo_id);


--
-- TOC entry 4880 (class 2606 OID 27402)
-- Name: historico_estadias historico_estadias_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4881 (class 2606 OID 27412)
-- Name: historico_estadias historico_estadias_habitacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_habitacion_id_fkey FOREIGN KEY (habitacion_id) REFERENCES public.habitaciones(habitacion_id);


--
-- TOC entry 4882 (class 2606 OID 27397)
-- Name: historico_estadias historico_estadias_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4883 (class 2606 OID 27407)
-- Name: historico_estadias historico_estadias_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_estadias
    ADD CONSTRAINT historico_estadias_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(reservacion_id);


--
-- TOC entry 4877 (class 2606 OID 27361)
-- Name: pagos pagos_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(reservacion_id);


--
-- TOC entry 4868 (class 2606 OID 27243)
-- Name: politicas_temporada politicas_temporada_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.politicas_temporada
    ADD CONSTRAINT politicas_temporada_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4873 (class 2606 OID 27311)
-- Name: reservacion_habitaciones reservacion_habitaciones_habitacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_habitaciones
    ADD CONSTRAINT reservacion_habitaciones_habitacion_id_fkey FOREIGN KEY (habitacion_id) REFERENCES public.habitaciones(habitacion_id);


--
-- TOC entry 4874 (class 2606 OID 27306)
-- Name: reservacion_habitaciones reservacion_habitaciones_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_habitaciones
    ADD CONSTRAINT reservacion_habitaciones_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(reservacion_id);


--
-- TOC entry 4875 (class 2606 OID 27328)
-- Name: reservacion_servicios reservacion_servicios_reservacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion_servicios
    ADD CONSTRAINT reservacion_servicios_reservacion_id_fkey FOREIGN KEY (reservacion_id) REFERENCES public.reservaciones(reservacion_id);


--
-- TOC entry 4871 (class 2606 OID 27290)
-- Name: reservaciones reservaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(cliente_id);


--
-- TOC entry 4872 (class 2606 OID 27285)
-- Name: reservaciones reservaciones_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservaciones
    ADD CONSTRAINT reservaciones_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4876 (class 2606 OID 27345)
-- Name: servicios_hotel servicios_hotel_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicios_hotel
    ADD CONSTRAINT servicios_hotel_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


--
-- TOC entry 4869 (class 2606 OID 27259)
-- Name: tarifas_temporada tarifas_temporada_politica_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifas_temporada
    ADD CONSTRAINT tarifas_temporada_politica_id_fkey FOREIGN KEY (politica_id) REFERENCES public.politicas_temporada(politica_id);


--
-- TOC entry 4870 (class 2606 OID 27264)
-- Name: tarifas_temporada tarifas_temporada_tipo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifas_temporada
    ADD CONSTRAINT tarifas_temporada_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES public.tipos_habitacion(tipo_id);


--
-- TOC entry 4865 (class 2606 OID 27204)
-- Name: tipos_habitacion tipos_habitacion_hotel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_habitacion
    ADD CONSTRAINT tipos_habitacion_hotel_id_fkey FOREIGN KEY (hotel_id) REFERENCES public.hoteles(hotel_id);


-- Completed on 2025-06-05 16:26:46

--
-- PostgreSQL database dump complete
--

