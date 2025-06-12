package com.nechavarria.proyecto2.model.entity;

import jakarta.persistence.*;
import java.time.LocalDate;

@Entity
@Table(name = "hoteles")
public class Hotel {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "hotel_id")
    private Integer id;

    @Column(name = "nombre", nullable = false, length = 100)
    private String nombre;

    @Column(name = "direccion", nullable = false, columnDefinition = "text")
    private String direccion;

    @Column(name = "ciudad",nullable = false, length = 50)
    private String ciudad;

    @Column(name = "pais",nullable = false, length = 50)
    private String pais;

    @Column(name = "telefono",nullable = false, length = 20)
    private String telefono;

    @Column(name = "direccion",nullable = false, length = 100)
    private String email;

    @Column(name = "estrellas")
    private Integer estrellas;

    @Column(name = "activo")
    private Boolean activo = true;

    @Column(name = "fecha_apertura")
    private LocalDate fechaApertura;

    @Column(name = "descripcion")
    private String descripcion;


    public Hotel() {}

    public Hotel (String nombre, String direccion, String ciudad, String pais, String telefono, String descripcion){
        this.nombre = nombre;
        this.direccion = direccion;
        this.ciudad = ciudad;
        this.pais = pais;
        this.telefono = telefono;
        this.descripcion = descripcion;
    }


    // Getters y Setters




    public Integer getId() {
        return id;
    }

    public void setId(Integer id) {
        this.id = id;
    }

    public String getNombre() {
        return nombre;
    }

    public void setNombre(String nombre) {
        this.nombre = nombre;
    }

    public String getDireccion() {
        return direccion;
    }

    public void setDireccion(String direccion) {
        this.direccion = direccion;
    }

    public String getCiudad() {
        return ciudad;
    }

    public void setCiudad(String ciudad) {
        this.ciudad = ciudad;
    }

    public String getPais() {
        return pais;
    }

    public void setPais(String pais) {
        this.pais = pais;
    }

    public String getTelefono() {
        return telefono;
    }

    public void setTelefono(String telefono) {
        this.telefono = telefono;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public Integer getEstrellas() {
        return estrellas;
    }

    public void setEstrellas(Integer estrellas) {
        this.estrellas = estrellas;
    }

    public Boolean getActivo() {
        return activo;
    }

    public void setActivo(Boolean activo) {
        this.activo = activo;
    }

    public LocalDate getFechaApertura() {
        return fechaApertura;
    }

    public void setFechaApertura(LocalDate fechaApertura) {
        this.fechaApertura = fechaApertura;
    }

    public String getDescripcion() {
        return descripcion;
    }

    public void setDescripcion(String descripcion) {
        this.descripcion = descripcion;
    }
}
