package com.nechavarria.proyecto2.model.entity;

import jakarta.persistence.*;

import java.math.BigDecimal;

/*
 * AUTOR: NELSON CHAVARRIA
 * NOTES: ELABORADO DE FORMA QUE LO SIGUIENTE SE ESTÉ IMPLEMENTADO CORRECTAMENTE
 * nombre_servicio, descripcion, precio_unitario, disponible (true/false)
**/

@Entity
@Table(name = "servicios_hotel")
public class ServicioHotel {


    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "servicio_id")
    public int servicio_id;

    @ManyToOne
    @JoinColumn(name = "hotel_id", referencedColumnName = "hotel_id")
    private Hotel hotel;

    @Column(name = "nombre") // post
    public String nombre;

    @Column(name = "descripcion") // post
    public String descripcion;

    @Column(name = "precio_base") // post
    public BigDecimal precio_unitario;

    public String categoria = "No definido";

    public String horario_disponibilidad = "No definido";

    @Column(name = "precio_base") // post
    public boolean disponible = true;

    // Constructor vacío para frameworks
    public ServicioHotel() {}

    // Constructor con campos obligatorios
    public ServicioHotel(String nombre,String descripcion, BigDecimal precio_base, boolean disponibilidad) {
        this.nombre = nombre;
        this.precio_unitario = precio_base;
        this.descripcion = descripcion;
        this.disponible = disponibilidad;
    }

    public int servicio_id() {
        return servicio_id;
    }

    public ServicioHotel setServicio_id(int servicio_id) {
        this.servicio_id = servicio_id;
        return this;
    }

    public Hotel hotel() {
        return hotel;
    }

    public ServicioHotel setHotel(Hotel hotel) {
        this.hotel = hotel;
        return this;
    }

    public String nombre() {
        return nombre;
    }

    public ServicioHotel setNombre(String nombre) {
        this.nombre = nombre;
        return this;
    }

    public String descripcion() {
        return descripcion;
    }

    public ServicioHotel setDescripcion(String descripcion) {
        this.descripcion = descripcion;
        return this;
    }

    public BigDecimal precio_unitario() {
        return precio_unitario;
    }

    public ServicioHotel setPrecio_unitario(BigDecimal precio_unitario) {
        this.precio_unitario = precio_unitario;
        return this;
    }

    public String categoria() {
        return categoria;
    }

    public ServicioHotel setCategoria(String categoria) {
        this.categoria = categoria;
        return this;
    }

    public String horario_disponibilidad() {
        return horario_disponibilidad;
    }

    public ServicioHotel setHorario_disponibilidad(String horario_disponibilidad) {
        this.horario_disponibilidad = horario_disponibilidad;
        return this;
    }

    public boolean disponible() {
        return disponible;
    }

    public ServicioHotel setDisponible(boolean disponible) {
        this.disponible = disponible;
        return this;
    }
}