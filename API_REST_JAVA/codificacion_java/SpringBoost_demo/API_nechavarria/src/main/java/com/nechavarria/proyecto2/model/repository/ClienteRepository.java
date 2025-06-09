package com.nechavarria.proyecto2.model.repository;

import com.nechavarria.proyecto2.model.entity.Cliente;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ClienteRepository extends JpaRepository<Cliente, Integer> {
    List<Cliente> findByNombreContainingIgnoreCaseAndEmailContainingIgnoreCaseAndNacionalidadContainingIgnoreCase(
            String nombre, String email, String nacionalidad);
}
