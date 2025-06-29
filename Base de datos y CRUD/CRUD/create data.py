import requests
import base64

# Configuración básica de autenticación
username = "Mimi"
password = "4332"
auth_string = f"{username}:{password}"
auth_bytes = auth_string.encode('ascii')
base64_auth = base64.b64encode(auth_bytes).decode('ascii')
headers = {
    "Authorization": f"Basic {base64_auth}",
    "Content-Type": "application/json"
}
base_url = "http://localhost:8080/clientes"

def crear_cliente():
    """Ejemplo de creación de un nuevo cliente"""
    print("\n--- Creando nuevo cliente ---")
    body = {
        "nombre": "Marlon",
        "apellido": "Angelo",
        "documentoIdentidad": "292901192",
        "tipoDocumento": "DNI",
        "nacionalidad": "Costa Rica",
        "telefono": "88888888",
        "email": "juan@example.com"
    }
    
    response = requests.post(base_url, json=body, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
    
    # Retornamos el ID del cliente creado (usando el campo "id" de la respuesta)
    if response.status_code == 200:
        return response.json().get('id')  # Cambiado de 'idCliente' a 'id'
    return None

def obtener_cliente(cliente_id):
    """Ejemplo de obtención de un cliente por ID"""
    print(f"\n--- Obteniendo cliente ID: {cliente_id} ---")
    url = f"{base_url}/{cliente_id}"
    response = requests.get(url, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    if response.status_code == 200:
        print("Cliente encontrado:")
        print(response.json())
    else:
        print(f"Response: {response.text}")

def listar_clientes():
    """Ejemplo de listado de clientes con filtros opcionales"""
    print("\n--- Listando clientes ---")
    params = {
        "nombre": "Marlon",  # Filtro opcional
        # "email": "juan@example.com",  # Otros filtros opcionales
        # "nacionalidad": "Costa Rica"
    }
    
    response = requests.get(f"{base_url}/ver", headers=headers, params=params)
    
    print(f"Status Code: {response.status_code}")
    if response.status_code == 200:
        print("Clientes encontrados:")
        for idx, cliente in enumerate(response.json(), 1):
            print(f"\nCliente #{idx}:")
            print(f"ID: {cliente.get('id')}")
            print(f"Nombre: {cliente.get('nombre')}")
            print(f"Email: {cliente.get('email')}")
            print(f"Activo: {cliente.get('activo')}")
    else:
        print(f"Response: {response.text}")

def actualizar_cliente(cliente_id):
    """Ejemplo de actualización de un cliente"""
    print(f"\n--- Actualizando cliente ID: {cliente_id} ---")
    url = f"{base_url}/{cliente_id}"
    body = {
        "nombre": "Marlon",
        "apellido": "Modificado",
        "documentoIdentidad": "922148201",
        "tipoDocumento": "DNI",
        "nacionalidad": "Costa Rica",
        "telefono": "71235293",
        "email": "martinactualizado@example.com"
    }
    
    response = requests.put(url, json=body, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")

def eliminar_cliente(cliente_id):
    """Ejemplo de eliminación de un cliente"""
    print(f"\n--- Eliminando cliente ID: {cliente_id} ---")
    url = f"{base_url}/{cliente_id}"
    response = requests.delete(url, headers=headers)
    
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")

# Ejecución de los ejemplos
if __name__ == "__main__":
    try:
        # 1. Crear un nuevo cliente
        print("=== EJEMPLO COMPLETO CRUD ===")
        cliente_id = crear_cliente()
        
        if cliente_id:
            # 2. Obtener el cliente recién creado
            obtener_cliente(cliente_id)
            
            # 3. Listar clientes (con filtro)
            listar_clientes()
            
            # 4. Actualizar el cliente
            actualizar_cliente(cliente_id)
            
            # 5. Verificar la actualización
            obtener_cliente(cliente_id)
            
            # 6. Eliminar el cliente 
            eliminar_cliente(cliente_id)
            
            # 7. Verificar que ya no existe
            listar_clientes()
    except Exception as e:
        print(f"\nOcurrió un error: {str(e)}")