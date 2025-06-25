package com.nechavarria.proyecto2.controllers;

import com.nechavarria.proyecto2.model.dto.PagoDto;
import com.nechavarria.proyecto2.model.entity.Pago;
import com.nechavarria.proyecto2.model.service.PagoService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/pagos")
public class PagoController {

    private final PagoService pagoService;

    @Autowired
    public PagoController(PagoService pagoService) {
        this.pagoService = pagoService;
    }

    @PostMapping
    public ResponseEntity<Pago> registrarPago(@RequestBody PagoDto pagoDto) {
        Pago nuevoPago = pagoService.registrarPago(pagoDto);
        return ResponseEntity.ok(nuevoPago);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Pago> obtenerPago(@PathVariable Integer id) {
        Pago pago = pagoService.obtenerPago(id);
        return ResponseEntity.ok(pago);
    }

    @GetMapping
    public ResponseEntity<List<Pago>> listarPagos(
            @RequestParam(required = false) Integer reservacionId,
            @RequestParam(required = false) String metodoPago) {

        if (reservacionId != null) {
            return ResponseEntity.ok(pagoService.listarPagosPorReservacion(reservacionId));
        }

        // Implementar más filtros según necesidad
        return ResponseEntity.notFound().build();
    }
}