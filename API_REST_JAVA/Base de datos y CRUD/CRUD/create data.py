import requests
import base64

# Configuración de autenticación Basic
username = "Mimi"
password = "4332"
auth_string = f"{username}:{password}"
auth_bytes = auth_string.encode('ascii')
base64_auth = base64.b64encode(auth_bytes).decode('ascii')
headers = {
    "Authorization": f"Basic {base64_auth}",
    "Content-Type": "application/json"
}

# Cuerpo de la solicitud
body = {
    "nombre": "Martin",
    "apellido": "Pellegrini",
    "documentoIdentidad": "292929292",
    "tipoDocumento": "DNI",
    "nacionalidad": "Costa Rica",
    "telefono": "88888888",
    "email": "juan@example.com"
}

# Realizar la solicitud POST
url = "http://localhost:8080/clientes"
response = requests.post(url, json=body, headers=headers)

# Mostrar la respuesta
print(f"Status Code: {response.status_code}")
print(f"Response: {response.text}")