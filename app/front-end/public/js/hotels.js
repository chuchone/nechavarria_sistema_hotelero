// Cargar habitaciones al abrir la página
document.addEventListener('DOMContentLoaded', async () => {
  try {
    const response = await fetch('http://localhost:3000/hoteles/1/habitaciones');
    const habitaciones = await response.json();
    
    const habitacionesSection = document.querySelector('#habitaciones');
    habitaciones.forEach(habitacion => {
      habitacionesSection.innerHTML += `
        <div class="room-card">
          <h3>Habitación ${habitacion.numero}</h3>
          <p>Tipo: ${habitacion.tipo_habitacion || 'Estándar'}</p>
          <p>Estado: ${habitacion.estado}</p>
        </div>
      `;
    });
  } catch (error) {
    console.error('Error:', error);
  }
});