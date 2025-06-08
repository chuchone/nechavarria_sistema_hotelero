package com.nechavarria.proyecto2.controllers;

import com.nechavarria.proyecto2.model.Cliente;
import com.nechavarria.proyecto2.service.ClienteService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/clientes")
public class ClienteController {

    @Autowired
    private ClienteService clienteService;// Ligado dinamico


    @PostMapping
    public ResponseEntity<Cliente> crearCliente(@RequestBody Cliente cliente) {
        return ResponseEntity.ok(clienteService.crearCliente(cliente));
    }

    @GetMapping("/{id}")
    public ResponseEntity<Cliente> obtenerCliente(@PathVariable Integer id) {
        return clienteService.obtenerClientePorId(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    public ResponseEntity<Cliente> actualizarCliente(@PathVariable Integer id, @RequestBody Cliente cliente) {
        return ResponseEntity.ok(clienteService.actualizarCliente(id, cliente));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<String> eliminarCliente(@PathVariable Integer id) {
        boolean eliminado = clienteService.eliminarCliente(id);
        return eliminado ? ResponseEntity.ok("Cliente eliminado")
                : ResponseEntity.status(HttpStatus.CONFLICT).body("No se puede eliminar. Tiene reservaciones activas.");
    }

    @GetMapping("/ver")
    public List<Cliente> listarClientes(
            @RequestParam(required = false) String nombre,
            @RequestParam(required = false) String email,
            @RequestParam(required = false) String nacionalidad) {
        return clienteService.obtenerTodos(nombre, email, nacionalidad);
    }
}

