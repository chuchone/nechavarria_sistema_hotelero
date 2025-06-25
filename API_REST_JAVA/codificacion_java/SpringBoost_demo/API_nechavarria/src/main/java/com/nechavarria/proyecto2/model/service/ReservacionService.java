package com.nechavarria.proyecto2.model.service;
import com.nechavarria.proyecto2.model.dto.ReservacionDto;
import com.nechavarria.proyecto2.model.entity.Reservacion;
import com.nechavarria.proyecto2.model.repository.ReservacionRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class ReservacionService {

    private final ReservacionRepository reservacionRepository;
    private final HabitacionService habitacionService;

    @Autowired
    public ReservacionService(ReservacionRepository reservacionRepository,
                              HabitacionService habitacionService) {
        this.reservacionRepository = reservacionRepository;
        this.habitacionService = habitacionService;
    }

    @Transactional
    public Reservacion crearReservacion(ReservacionDto reservacionDto) {
        // Verificar disponibilidad primero
        boolean disponible = habitacionService.verificarDisponibilidad(
                reservacionDto.getHabitacionId(),
                reservacionDto.getFechaEntrada(),
                reservacionDto.getFechaSalida()
        );

        if (!disponible) {
            throw new RuntimeException("Habitación no disponible para las fechas seleccionadas");
        }

        // Llamar al procedimiento almacenado
        String resultado = reservacionRepository.crearReservacion(
                reservacionDto.getClienteId(),
                reservacionDto.getHabitacionId(),
                reservacionDto.getFechaEntrada(),
                reservacionDto.getFechaSalida(),
                reservacionDto.getNumeroHuespedes(),
                reservacionDto.getSolicitudesEspeciales(),
                reservacionDto.getTarifaAplicada()
        );

        // Buscar y retornar la reservación creada
        // (Necesitarás implementar una forma de obtener el ID de la nueva reservación)
        return obtenerUltimaReservacionCliente(reservacionDto.getClienteId());
    }

    public List<Reservacion> listarReservacionesPorCliente(Integer clienteId) {
        return reservacionRepository.findByClienteId(clienteId);
    }

    public Reservacion obtenerReservacion(Integer id) {
        return reservacionRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Reservación no encontrada"));
    }

    private Reservacion obtenerUltimaReservacionCliente(Integer clienteId) {
        List<Reservacion> reservaciones = reservacionRepository.findByClienteId(clienteId);
        if (reservaciones.isEmpty()) {
            throw new RuntimeException("No se pudo recuperar la reservación creada");
        }
        return reservaciones.get(reservaciones.size() - 1);
    }
}