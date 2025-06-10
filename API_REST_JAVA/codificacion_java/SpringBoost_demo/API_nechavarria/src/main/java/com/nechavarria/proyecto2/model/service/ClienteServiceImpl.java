package com.nechavarria.proyecto2.model.service;

import com.nechavarria.proyecto2.capaDatos.ValidacionesFormato;
import com.nechavarria.proyecto2.model.entity.Cliente;
import com.nechavarria.proyecto2.model.repository.ClienteRepository;
import com.nechavarria.proyecto2.model.repository.ReservacionRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import static com.nechavarria.proyecto2.capaDatos.ValidacionesFormato.*;

import java.util.List;
import java.util.Optional;

@Service
public class ClienteServiceImpl implements ClienteService {

    @Autowired
    private ClienteRepository repo;

    @Autowired
    private ReservacionRepository reservacionRepo;

    @Override
    public Cliente crearCliente(Cliente cliente) {
        ValidacionesFormato.validarEmail(cliente.getEmail());
        return repo.save(cliente);
    }

    @Override
    public Optional<Cliente> obtenerClientePorId(Integer id) {
        return repo.findById(id);
    }

    @Override
    public List<Cliente> obtenerTodos(String nombre, String email, String nacionalidad) {
        return repo.findByNombreContainingIgnoreCaseAndEmailContainingIgnoreCaseAndNacionalidadContainingIgnoreCase(
                nombre != null ? nombre : "",
                email != null ? email : "",
                nacionalidad != null ? nacionalidad : ""
        );
    }

    @Override
    public Cliente actualizarCliente(Integer id, Cliente cliente) {
        Cliente actual = repo.findById(id).orElseThrow();
        cliente.setId(id);
        return repo.save(cliente);
    }

    @Override
    public boolean eliminarCliente(Integer id) {
        if (reservacionRepo.existsByClienteIdAndEstado(id, "confirmada")) {
            return false;
        }
        repo.deleteById(id);
        return true;
    }


}
