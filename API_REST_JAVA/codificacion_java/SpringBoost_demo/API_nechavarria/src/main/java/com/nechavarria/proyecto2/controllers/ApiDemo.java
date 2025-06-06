package com.nechavarria.proyecto2.controllers;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("api")
public class ApiDemo {

    @GetMapping("/Saludar")
    public String saludar() {

        return "Hola, mundo, vengo a saludar";

    }
}
