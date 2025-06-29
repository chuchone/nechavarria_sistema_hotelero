from locust import HttpUser, task, between
import base64

class ApiUser(HttpUser):
    wait_time = between(1, 5)
    
    def on_start(self):
        # Configuración de autenticación
        username = "Mimi"
        password = "4332"
        auth_string = f"{username}:{password}"
        auth_bytes = auth_string.encode('ascii')
        self.base64_auth = base64.b64encode(auth_bytes).decode('ascii')
        self.headers = {
            "Authorization": f"Basic {self.base64_auth}",
            "Content-Type": "application/json"
        }
    
    @task
    def crear_cliente(self):
        body = {
            "nombre": "Marlon",
            "apellido": "Angelo",
            "documentoIdentidad": "292901192",
            "tipoDocumento": "DNI",
            "nacionalidad": "Costa Rica",
            "telefono": "88888888",
            "email": "juan@example.com"
        }
        self.client.post("/clientes", json=body, headers=self.headers)
    
    @task(3)  # Se ejecutará 3 veces más que 'crear_cliente'
    def obtener_clientes(self):
        self.client.get("/clientes/ver", headers=self.headers)
    
    @task(2)  # Se ejecutará 2 veces más que 'crear_cliente'
    def actualizar_cliente(self):
        body = {
            "nombre": "Marlon Actualizado",
            "apellido": "Modificado",
            "documentoIdentidad": "922148201",
            "tipoDocumento": "DNI",
            "nacionalidad": "Costa Rica",
            "telefono": "71235293",
            "email": "martinactualizado@example.com"
        }
        self.client.put("/clientes/1", json=body, headers=self.headers)