package com.nechavarria.proyecto2.repository;

import com.nechavarria.proyecto2.model.Reservacion;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReservacionRepository extends JpaRepository<Reservacion, Integer> {
    boolean existsByClienteIdAndActivaTrue(Integer clienteId);
}
