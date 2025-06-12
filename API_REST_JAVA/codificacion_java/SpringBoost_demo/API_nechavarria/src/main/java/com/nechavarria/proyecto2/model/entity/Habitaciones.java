package com.nechavarria.proyecto2.model.entity;

/*
 * AUTOR: NELSON CHAVARRIA
 * NOTES: ELABORADO DE FORMA QUE LO SIGUIENTE SE ESTÉ IMPLEMENTADO CORRECTAMENTE
 * numero, tipo, descripcion, precio_noche, disponibilidad (true/false)
 **/



import jakarta.persistence.*;

@Entity
@Table(name = "habitaciones")
public class Habitaciones {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "habitacion_id")
    private static int habitacion_id;

    @ManyToOne
    @JoinColumn(name = "hotel_id", referencedColumnName = "hotel_id")
    private Hotel hotel;

    @Column(name = "numero")
    private String numero;

    @Column(name = "descripcion")
    private String descripcion;

    @Column(name = "tipo_id")
    private Integer tipo_id = 3; // POR DEFECTO, SE PUEDE HACER UN SET PERFECTAMENTE

    @Column(name = "precio_habitacion")
    private double precio_noche;

    @Column(name = "esta_ocupada")
    private boolean disponibilidad;

    @Column(name = "piso") // Irrelevante para la prueba de carga
    private int piso = 1;

    @Column(name = "caracteristicas_especiales")
    private String caracteristicas_especiales = "No especificado";

    @Column(name = "estado")
    private String estado = "disponible";

    @Column(name = "notas")
    private String notas = "Nada especificado";


    // Constructor vacío para frameworks
    public Habitaciones() {}

    // Constructor con campos obligatorios
    public Habitaciones(String numero, String descripcion, double precio_noche, boolean disponibilidad) {
        this.numero = numero;
        this.descripcion = descripcion;
        this.precio_noche = precio_noche;
        this.disponibilidad = disponibilidad;

    }

    public static int habitacion_id() {
        return habitacion_id;
    }

    public static void setHabitacion_id(int habitacion_id) {
        Habitaciones.habitacion_id = habitacion_id;
    }

    public Hotel hotel() {
        return hotel;
    }

    public Habitaciones setHotel(Hotel hotel) {
        this.hotel = hotel;
        return this;
    }

    public String numero() {
        return numero;
    }

    public Habitaciones setNumero(String numero) {
        this.numero = numero;
        return this;
    }

    public String descripcion() {
        return descripcion;
    }

    public Habitaciones setDescripcion(String descripcion) {
        this.descripcion = descripcion;
        return this;
    }

    public Integer tipo_id() {
        return tipo_id;
    }

    public Habitaciones setTipo_id(Integer tipo_id) {
        this.tipo_id = tipo_id;
        return this;
    }

    public double precio_noche() {
        return precio_noche;
    }

    public Habitaciones setPrecio_noche(double precio_noche) {
        this.precio_noche = precio_noche;
        return this;
    }

    public boolean disponibilidad() {
        return disponibilidad;
    }

    public Habitaciones setDisponibilidad(boolean disponibilidad) {
        this.disponibilidad = disponibilidad;
        return this;
    }

    public int piso() {
        return piso;
    }

    public Habitaciones setPiso(int piso) {
        this.piso = piso;
        return this;
    }

    public String caracteristicas_especiales() {
        return caracteristicas_especiales;
    }

    public Habitaciones setCaracteristicas_especiales(String caracteristicas_especiales) {
        this.caracteristicas_especiales = caracteristicas_especiales;
        return this;
    }

    public String estado() {
        return estado;
    }

    public Habitaciones setEstado(String estado) {
        this.estado = estado;
        return this;
    }

    public String notas() {
        return notas;
    }

    public Habitaciones setNotas(String notas) {
        this.notas = notas;
        return this;
    }
}