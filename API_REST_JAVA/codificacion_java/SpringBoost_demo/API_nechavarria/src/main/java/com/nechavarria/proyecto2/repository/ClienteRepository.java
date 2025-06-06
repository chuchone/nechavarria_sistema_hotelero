package com.nechavarria.proyecto2.repository;

import com.nechavarria.proyecto2.model.clientes;
import org.springframework.data.repository.CrudRepository;

public interface ClienteRepository extends CrudRepository<clientes, Integer> {
}
