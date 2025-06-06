package com.nechavarria.proyecto2.service;

import java.util.ArrayList;
import java.util.Optional;

import com.nechavarria.proyecto2.model.clientes;

public interface ClienteService {
    ArrayList<clientes> getAllUser();
    Optional<clientes> getUserById(Integer id);
    clientes saveUser(clientes cliente);
    String deleteUserById(Integer id);
}
