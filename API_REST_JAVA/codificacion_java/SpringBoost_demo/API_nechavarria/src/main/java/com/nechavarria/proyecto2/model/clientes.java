package com.nechavarria.proyecto2.model;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;

import java.time.LocalDateTime;

@Entity
public class clientes {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer cliente_id;

    public String nombre;
    public String documento_identidad;
    public String tipo_documento = "Costarricense";
    public String nacionalidad;
    public String telefono;
    public String email;
    public LocalDateTime fecha_registro;
    public boolean activo;
    public String preferencias;
    public String alergias;
    public String password_hash;

    // Constructor vacío para frameworks
    public clientes() {}

    // Constructor con campos obligatorios
    public clientes(String nombre, String apellido, String documento_identidad, String tipo_documento ,
                    String nacionalidad, String telefono, String email) {
        this.nombre = nombre +" "+ apellido;
        this.documento_identidad = documento_identidad;
        this.tipo_documento = tipo_documento;
        this.nacionalidad = nacionalidad;
        this.telefono = telefono;
        this.email = email;
        this.fecha_registro = LocalDateTime.now();
        this.activo = true;
    }

    public int getCliente_id() {
        return cliente_id;
    }
    public void setCliente_id(int cliente_id) {
        this.cliente_id = cliente_id;
    }



}