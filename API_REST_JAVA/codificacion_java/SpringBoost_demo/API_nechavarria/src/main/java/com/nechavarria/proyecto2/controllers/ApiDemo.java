package com.nechavarria.proyecto2.controllers;

import com.nechavarria.proyecto2.model.clientes;
import com.nechavarria.proyecto2.repository.ClienteRepository;
import com.nechavarria.proyecto2.service.ClienteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.Optional;

@RestController
@RequestMapping("api")
public class ApiDemo  {

    @Autowired
    ClienteService clienteService;

    @GetMapping("/Saludar")
    public String saludar() {

        return "Hola, mundo, vengo a saludar";

    }

    @GetMapping("/all")
    public ArrayList<clientes> getAllUser() {
        return clienteService.getAllUser();
    }

    @GetMapping("/find/{id}")
    public Optional<clientes> getUserById(Integer id) {
        return clienteService.getUserById(id);

    }

    @PostMapping("/save")
    public clientes saveUser(@RequestBody clientes cliente) {
        return clienteService.saveUser(cliente);
    }

    @DeleteMapping("/delete/{id}")
    public String deleteUserById(@PathVariable Integer id) {
        if(clienteService.deleteUserById(id).equals("Eliminado")){
            return "Usuario eliminado";
        }
        else{
            return "No se puede eliminar el usuario";
        }
    }

}
