package com.nechavarria.proyecto2.model.repository;

import com.nechavarria.proyecto2.model.entity.Reservacion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.query.Procedure;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public interface ReservacionRepository extends JpaRepository<Reservacion, Integer> {

    @Procedure(name = "sp_crear_reservacion")
    String crearReservacion(
            @Param("p_id_cliente") Integer clienteId,
            @Param("p_id_habitacion") Integer habitacionId,
            @Param("p_fecha_entrada") LocalDate fechaEntrada,
            @Param("p_fecha_salida") LocalDate fechaSalida,
            @Param("p_numero_huespedes") Integer numeroHuespedes,
            @Param("p_solicitudes_especiales") String solicitudesEspeciales,
            @Param("p_tarifa_aplicada") BigDecimal tarifaAplicada
    );

    List<Reservacion> findByClienteId(Integer clienteId);

    boolean existsByClienteIdAndEstado(Integer id, String confirmada);
}