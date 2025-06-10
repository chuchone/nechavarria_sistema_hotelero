package com.nechavarria.proyecto2.capaDatos;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.config.annotation.authentication.builders.AuthenticationManagerBuilder;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;

@Configuration
public class SecurityDatabaseConfig {


    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .anyRequest().authenticated()
                )
                .httpBasic(httpBasicConfig -> {})  // Configuración básica sin cambios adicionales
                .csrf(csrfConfig -> csrfConfig.disable());

        return http.build();
    }

    @Bean
    public InMemoryUserDetailsManager userDetailsService() {
        var user = User.withUsername("Mimi")
                .password("{noop}4332") // No se exigía cifrado en los requerimientos así que se omite
                .roles("ADMIN")
                .build();
        return new InMemoryUserDetailsManager(user);
    }
}