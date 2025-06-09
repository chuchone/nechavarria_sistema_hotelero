package com.nechavarria.proyecto2.model.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "clientes")
public class Cliente {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "cliente_id")
    private Integer id;

    @Column(nullable = false, length = 100)
    private String nombre;

    @Column(name = "documento_identidad", nullable = false, length = 20)
    private String documentoIdentidad;

    @Column(name = "tipo_documento", nullable = false, length = 20)
    private String tipoDocumento;

    @Column(nullable = false, length = 50)
    private String nacionalidad;

    @Column(nullable = false, length = 20)
    private String telefono;

    @Column(nullable = false, length = 100)
    private String email;

    @Column(name = "fecha_registro")
    private LocalDateTime fechaRegistro = LocalDateTime.now();

    private Boolean activo = true;

    private String preferencias;
    private String alergias;

    @Column(name = "password_hash")
    private String passwordHash;



    // Constructor vacío para frameworks
    public Cliente() {}

    // Constructor con campos obligatorios
    public Cliente(String nombre, String apellido, String documento_identidad, String tipo_documento ,
                   String nacionalidad, String telefono, String email) {
        this.nombre = nombre +" "+ apellido;
        this.documentoIdentidad = documento_identidad;
        this.tipoDocumento = tipo_documento;
        this.nacionalidad = nacionalidad;
        this.telefono = telefono;
        this.email = email;
        this.fechaRegistro = LocalDateTime.now();
        this.activo = true;
    }




    public void setId(Integer id) {
        this.id = id;
    }

    public void setNombre(String nombre) {
        this.nombre = nombre;
    }


    public String tipoDocumento() {
        return tipoDocumento;
    }

    public Cliente setTipoDocumento(String tipoDocumento) {
        this.tipoDocumento = tipoDocumento;
        return this;
    }

    public String documentoIdentidad() {
        return documentoIdentidad;
    }

    public Cliente setDocumentoIdentidad(String documentoIdentidad) {
        this.documentoIdentidad = documentoIdentidad;
        return this;
    }

    public String nacionalidad() {
        return nacionalidad;
    }

    public Cliente setNacionalidad(String nacionalidad) {
        this.nacionalidad = nacionalidad;
        return this;
    }

    public String telefono() {
        return telefono;
    }

    public Cliente setTelefono(String telefono) {
        this.telefono = telefono;
        return this;
    }

    public Integer getId() {
        return id;
    }

    public String getNombre() {
        return nombre;
    }

    public String getEmail() {
        return email;
    }

    public Cliente setEmail(String email) {
        this.email = email;
        return this;
    }

    public LocalDateTime fechaRegistro() {
        return fechaRegistro;
    }

    public Cliente setFechaRegistro(LocalDateTime fechaRegistro) {
        this.fechaRegistro = fechaRegistro;
        return this;
    }

    public Boolean getActivo() {
        return activo;
    }

    public Cliente setActivo(Boolean activo) {
        this.activo = activo;
        return this;
    }

    public String getPreferencias() {
        return preferencias;
    }

    public Cliente setPreferencias(String preferencias) {
        this.preferencias = preferencias;
        return this;
    }

    public String getAlergias() {
        return alergias;
    }

    public Cliente setAlergias(String alergias) {
        this.alergias = alergias;
        return this;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public Cliente setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
        return this;
    }
}