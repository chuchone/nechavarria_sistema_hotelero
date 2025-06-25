package com.nechavarria.proyecto2.model.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;
import java.math.BigDecimal;


/*
 * AUTOR: NELSON CHAVARRIA
 * NOTES: ELABORADO DE FORMA QUE LO SIGUIENTE SE ESTÉ IMPLEMENTADO CORRECTAMENTE
 * id_reservacion, monto, metodo_pago (tarjeta, efectivo, transferencia), fecha_pago, referencia_pago
 **/


@Entity
@Table(name = "pagos")
public class Pago {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "pago_id")
    private int pago_id;

    @ManyToOne
    @JoinColumn(name = "reservacion_id", nullable = false)
    private Reservacion reservacion;

    @Column(name = "monto")
    private BigDecimal monto;

    @Column(name = "metodo_pago", nullable = false, length = 100)
    private String metodo_pago;

    @Column(name = "fecha_pago")
    private LocalDateTime fecha_pago = LocalDateTime.now();

    @Column(name = "estado")
    private String estado;

    @Column(name = "referencia")
    private String referencia;

    @Column(name = "descripcion")
    private String descripcion;

    // Constructor vacío para frameworks
    public Pago() {}

    // Constructor con campos obligatorios
    public Pago(BigDecimal monto, String metodo_pago, String estado) {
        this.monto = monto;
        this.metodo_pago = metodo_pago;
        this.estado = estado;
        this.fecha_pago = LocalDateTime.now();
    }

    public int pago_id() {
        return pago_id;
    }

    public Pago setPago_id(int pago_id) {
        this.pago_id = pago_id;
        return this;
    }

    public Reservacion reservacion() {
        return reservacion;
    }

    public Pago setReservacion(Reservacion reservacion) {
        this.reservacion = reservacion;
        return this;
    }

    public BigDecimal monto() {
        return monto;
    }

    public Pago setMonto(BigDecimal monto) {
        this.monto = monto;
        return this;
    }

    public String metodo_pago() {
        return metodo_pago;
    }

    public Pago setMetodo_pago(String metodo_pago) {
        this.metodo_pago = metodo_pago;
        return this;
    }

    public LocalDateTime fecha_pago() {
        return fecha_pago;
    }

    public Pago setFecha_pago(LocalDateTime fecha_pago) {
        this.fecha_pago = fecha_pago;
        return this;
    }

    public String estado() {
        return estado;
    }

    public Pago setEstado(String estado) {
        this.estado = estado;
        return this;
    }

    public String referencia() {
        return referencia;
    }

    public Pago setReferencia(String referencia) {
        this.referencia = referencia;
        return this;
    }

    public String descripcion() {
        return descripcion;
    }

    public Pago setDescripcion(String descripcion) {
        this.descripcion = descripcion;
        return this;
    }
}