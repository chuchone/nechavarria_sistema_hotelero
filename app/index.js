const os =  require('node:os')

console.log('Informacion del sistema operativo:')
console.log("..............-----...............")
console.log("nombre del sistema operativo", os.platform())
console.log("version del sistema operativo", os.release())
console.log("arquitectura del sistema operativo", os.arch())
