package com.nechavarria.proyecto2.model.dto;

import lombok.Data;

import java.math.BigDecimal;

@Data
public class PagoDto {
    private Integer reservacionId;
    private BigDecimal monto;
    private String metodoPago;
    private String referencia;
    private String descripcion;
}