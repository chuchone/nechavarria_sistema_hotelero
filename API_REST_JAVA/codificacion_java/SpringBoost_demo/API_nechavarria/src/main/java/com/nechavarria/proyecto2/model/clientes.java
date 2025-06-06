package com.nechavarria.proyecto2.model;

import java.time.LocalDateTime;

public class clientes {
    public int cliente_id;
    public String nombre;
    public String documento_identidad;
    public String tipo_documento;
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
    public clientes(String nombre, String documento_identidad, String tipo_documento,
                   String nacionalidad, String telefono, String email) {
        this.nombre = nombre;
        this.documento_identidad = documento_identidad;
        this.tipo_documento = tipo_documento;
        this.nacionalidad = nacionalidad;
        this.telefono = telefono;
        this.email = email;
        this.fecha_registro = LocalDateTime.now();
        this.activo = true;
    }
}