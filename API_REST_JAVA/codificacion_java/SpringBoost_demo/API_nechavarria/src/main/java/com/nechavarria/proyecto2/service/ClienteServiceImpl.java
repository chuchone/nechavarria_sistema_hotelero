package com.nechavarria.proyecto2.service;

import com.nechavarria.proyecto2.model.clientes;
import com.nechavarria.proyecto2.repository.ClienteRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Optional;

@Service
public class ClienteServiceImpl implements ClienteService {
    @Autowired
    ClienteRepository clienteRepository;

    @Override
    public ArrayList<clientes> getAllUser() {
        return (ArrayList<clientes>) clienteRepository.findAll();
    }

    @Override
    public Optional<clientes> getUserById(Integer id) {
        return clienteRepository.findById(id);
    }

    @Override
    public clientes saveUser(clientes cliente) {
        return clienteRepository.save(cliente);
    }

    @Override
    public String deleteUserById(Integer id) {
        try {
            Optional<clientes> u = getUserById(id);
            clienteRepository.delete(u.get());
            return "Eliminado";
        }catch(Exception e){
            return "No eliminado";
        }
    }
}
