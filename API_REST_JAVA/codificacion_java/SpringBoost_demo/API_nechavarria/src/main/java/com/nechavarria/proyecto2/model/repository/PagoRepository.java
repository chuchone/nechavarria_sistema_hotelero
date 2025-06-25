package com.nechavarria.proyecto2.model.repository;

import com.nechavarria.proyecto2.model.entity.Pago;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.query.Procedure;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;

public interface PagoRepository extends JpaRepository<Pago, Integer> {

    @Procedure(name = "sp_registrar_pago")
    String registrarPago(
            @Param("p_reservacion_id") Integer reservacionId,
            @Param("p_monto") BigDecimal monto,
            @Param("p_metodo_pago") String metodoPago,
            @Param("p_referencia") String referencia,
            @Param("p_descripcion") String descripcion
    );

    List<Pago> findByReservacionId(Integer reservacionId);
}