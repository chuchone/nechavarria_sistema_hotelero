package com.nechavarria.proyecto2.capaDatos;

public class ValidacionesFormato {
    public static void validarEmail(String email) {
        if (!email.matches("^(.+)@(.+)$")) {
            throw new IllegalArgumentException("Formato de email inválido.");
        }
    }
}
