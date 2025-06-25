package com.nechavarria.proyecto2.model.service;

import com.nechavarria.proyecto2.model.dto.PagoDto;
import com.nechavarria.proyecto2.model.entity.Pago;
import com.nechavarria.proyecto2.model.entity.Reservacion;
import com.nechavarria.proyecto2.model.repository.PagoRepository;
import com.nechavarria.proyecto2.model.repository.ReservacionRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class PagoService {

    private final PagoRepository pagoRepository;
    private final ReservacionRepository reservacionRepository;

    @Autowired
    public PagoService(PagoRepository pagoRepository,
                       ReservacionRepository reservacionRepository) {
        this.pagoRepository = pagoRepository;
        this.reservacionRepository = reservacionRepository;
    }

    @Transactional
    public Pago registrarPago(PagoDto pagoDto) {
        // Verificar que la reservación existe
        Reservacion reservacion = reservacionRepository.findById(pagoDto.getReservacionId())
                .orElseThrow(() -> new RuntimeException("Reservación no encontrada"));

        // Registrar el pago mediante el procedimiento almacenado
        String resultado = pagoRepository.registrarPago(
                pagoDto.getReservacionId(),
                pagoDto.getMonto(),
                pagoDto.getMetodoPago(),
                pagoDto.getReferencia(),
                pagoDto.getDescripcion()
        );

        // Obtener y retornar el último pago registrado para esta reservación
        return obtenerUltimoPagoReservacion(pagoDto.getReservacionId());
    }

    public List<Pago> listarPagosPorReservacion(Integer reservacionId) {
        return pagoRepository.findByReservacionId(reservacionId);
    }

    public Pago obtenerPago(Integer id) {
        return pagoRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Pago no encontrado"));
    }

    private Pago obtenerUltimoPagoReservacion(Integer reservacionId) {
        List<Pago> pagos = pagoRepository.findByReservacionId(reservacionId);
        if (pagos.isEmpty()) {
            throw new RuntimeException("No se pudo recuperar el pago registrado");
        }
        return pagos.get(pagos.size() - 1);
    }
}