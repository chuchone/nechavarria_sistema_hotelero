package com.nechavarria.proyecto2.model.entity;

import jakarta.persistence.*;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Date;


/*
 * AUTOR: NELSON CHAVARRIA
 * NOTES: ELABORADO DE FORMA QUE LO SIGUIENTE SE ESTÉ IMPLEMENTADO CORRECTAMENTE
 * id_cliente, id_habitacion, fecha_entrada, fecha_salida, numero_huespedes, solicitudes_especiales
 **/


@Entity
@Table(name = "reservaciones")
public class Reservacion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "reservacion_id")
    private Integer id;

    @ManyToOne
    @JoinColumn(name = "hotel_id")
    private Hotel hotel;

    @ManyToOne
    @JoinColumn(name = "cliente_id")
    private Cliente cliente;

    @Column(name = "fecha_creacion")
    private LocalDateTime fechaCreacion = LocalDateTime.now();

    @Column(name = "fecha_entrada", nullable = false)
    private LocalDate fechaEntrada;

    @Column(name = "fecha_salida", nullable = false)
    private LocalDate fechaSalida;

    @Column(name = "huespedes")
    private Integer numero_huespedes;

    @Column(nullable = false, length = 20)
    private String estado = "confirmada"; // Partiendo de que si se crea el objeto, es porque se confirmó

    @Column(name = "tipo_reserva", nullable = false, length = 20)
    private String tipoReserva;

    @Column(name = "solicitudes_especiales", columnDefinition = "text")
    private String solicitudesEspeciales = "No se especifica";

    @Column(name = "codigo_reserva", length = 20)
    private String codigoReserva;


    public Reservacion (){}

    public Reservacion (Hotel hotel, Cliente cliente, LocalDateTime fechaSalida, LocalDateTime fechaEntrada, Integer numero_huespedes, String solicitudesEspeciales) {
        this.hotel = hotel;
        this.cliente = cliente;
        this.fechaEntrada = LocalDate.from(fechaEntrada);
        this.fechaSalida = LocalDate.from(fechaSalida);
        this.numero_huespedes = numero_huespedes;
        this.solicitudesEspeciales = solicitudesEspeciales;
    }


    // Getters y Setters

    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public Hotel getHotel() {
        return hotel;
    }

    public void setHotel(Hotel hotel) {
        this.hotel = hotel;
    }

    public Cliente getCliente() {
        return cliente;
    }

    public void setCliente(Cliente cliente) {
        this.cliente = cliente;
    }

    public LocalDateTime getFechaCreacion() {
        return fechaCreacion;
    }

    public void setFechaCreacion(LocalDateTime fechaCreacion) {
        this.fechaCreacion = fechaCreacion;
    }

    public LocalDate getFechaEntrada() {
        return fechaEntrada;
    }

    public void setFechaEntrada(LocalDate fechaEntrada) {
        this.fechaEntrada = fechaEntrada;
    }

    public LocalDate getFechaSalida() {
        return fechaSalida;
    }

    public void setFechaSalida(LocalDate fechaSalida) {
        this.fechaSalida = fechaSalida;
    }


    public String getEstado() {
        return estado;
    }

    public void setEstado(String estado) {
        this.estado = estado;
    }

    public String getTipoReserva() {
        return tipoReserva;
    }

    public void setTipoReserva(String tipoReserva) {
        this.tipoReserva = tipoReserva;
    }

    public String getSolicitudesEspeciales() {
        return solicitudesEspeciales;
    }

    public void setSolicitudesEspeciales(String solicitudesEspeciales) {
        this.solicitudesEspeciales = solicitudesEspeciales;
    }

    public String getCodigoReserva() {
        return codigoReserva;
    }

    public void setCodigoReserva(String codigoReserva) {
        this.codigoReserva = codigoReserva;
    }
}
