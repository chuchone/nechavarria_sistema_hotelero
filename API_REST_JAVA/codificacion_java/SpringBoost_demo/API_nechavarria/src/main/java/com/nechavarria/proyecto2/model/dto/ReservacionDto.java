package com.nechavarria.proyecto2.model.dto;

import lombok.Data;

import java.time.LocalDate;

@Data
public class ReservacionDto {
    private Integer hotelId;
    private Integer clienteId;
    private LocalDate fechaEntrada;
    private LocalDate fechaSalida;
    private Integer numeroHuespedes;
    private String solicitudesEspeciales;
}
