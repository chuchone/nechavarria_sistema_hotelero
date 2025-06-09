package com.nechavarria.proyecto2.model.repository;

import com.nechavarria.proyecto2.model.entity.Reservacion;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReservacionRepository extends JpaRepository<Reservacion, Integer> {
    boolean existsByClienteIdAndEstado(Integer clienteId, String estado);
}
