package com.nechavarria.proyecto2.controllers;

import com.nechavarria.proyecto2.model.dto.ReservacionDto;
import com.nechavarria.proyecto2.model.entity.Reservacion;
import com.nechavarria.proyecto2.model.service.ReservacionService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/reservaciones")
public class ReservacionController {

    private final ReservacionService reservacionService;

    @Autowired
    public ReservacionController(ReservacionService reservacionService) {
        this.reservacionService = reservacionService;
    }

    @PostMapping
    public ResponseEntity<Reservacion> crearReservacion(@RequestBody ReservacionDto reservacionDto) {
        Reservacion nuevaReservacion = reservacionService.crearReservacion(reservacionDto);
        return ResponseEntity.ok(nuevaReservacion);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Reservacion> obtenerReservacion(@PathVariable Integer id) {
        Reservacion reservacion = reservacionService.obtenerReservacion(id);
        return ResponseEntity.ok(reservacion);
    }

    @GetMapping
    public ResponseEntity<List<Reservacion>> listarReservacionesPorCliente(
            @RequestParam(required = false) Integer clienteId) {
        if (clienteId != null) {
            return ResponseEntity.ok(reservacionService.listarReservacionesPorCliente(clienteId));
        }
        // queda pendiente agregar logica si no se especifica cliente, la base de datos si lo maneja

        return ResponseEntity.notFound().build();
    }
}