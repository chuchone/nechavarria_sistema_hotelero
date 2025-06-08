package com.nechavarria.proyecto2.model;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class Reservacion {


    public static int reservacion_id;

    public Integer hotel_id;
    public Integer cliente_id;
    public Integer id_habitacion;
    public LocalDateTime fecha_creacion;
    public LocalDate fecha_entrada;
    public LocalDate fecha_salida;
    public int adultos;
    public int ninos = 0;
    public String estado;
    public String tipo_reserva;
    public String solicitudes_especiales;
    public String codigo_reserva;

    // Constructor vacío para frameworks
    public Reservacion() {}

    // Constructor con campos obligatorios
    public Reservacion(LocalDate fecha_entrada, LocalDate fecha_salida,
                         int adultos, String estado, String tipo_reserva, int id_habitacion) {
        this.fecha_entrada = fecha_entrada;
        this.fecha_salida = fecha_salida;
        this.adultos = adultos;
        this.estado = estado;
        this.tipo_reserva = tipo_reserva;
        this.fecha_creacion = LocalDateTime.now(); // debatible
        this.id_habitacion = id_habitacion;
    }

    public static void set_id (int id) {
        reservacion_id = id;
    }

}