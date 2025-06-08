package com.nechavarria.proyecto2.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import com.nechavarria.proyecto2.model.Cliente;
import org.springframework.stereotype.Service;

@Service
public interface ClienteService {
    Cliente crearCliente(Cliente cliente);
    Optional<Cliente> obtenerClientePorId(Integer id);
    List<Cliente> obtenerTodos(String nombre, String email, String nacionalidad);
    Cliente actualizarCliente(Integer id, Cliente cliente);
    boolean eliminarCliente(Integer id);
}
