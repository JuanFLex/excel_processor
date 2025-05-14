import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "status" ]
  
  connect() {
    if (this.statusTarget.dataset.status !== "completed" && this.statusTarget.dataset.status !== "failed") {
      this.startPolling()
    }
  }
  
  disconnect() {
    this.stopPolling()
  }
  
  startPolling() {
    this.pollingId = setInterval(() => {
      this.checkStatus()
    }, 5000) // Verificar cada 5 segundos
  }
  
  stopPolling() {
    if (this.pollingId) {
      clearInterval(this.pollingId)
    }
  }
  
  checkStatus() {
    const url = this.statusTarget.dataset.url
    
    fetch(url)
      .then(response => response.json())
      .then(data => {
        // Actualizar el elemento de estado
        const statusElement = this.statusTarget
        const currentStatus = statusElement.dataset.status
        const newStatus = data.status
        
        if (currentStatus !== newStatus) {
          statusElement.dataset.status = newStatus
          statusElement.textContent = newStatus.charAt(0).toUpperCase() + newStatus.slice(1)
          
          // Actualizar la clase CSS
          statusElement.className = this.getStatusClass(newStatus)
          
          // Si el estado es "completed" o "failed", dejar de verificar
          if (newStatus === "completed" || newStatus === "failed") {
            this.stopPolling()
            
            // Recargar la página para mostrar los resultados
            window.location.reload()
          }
        }
      })
      .catch(error => {
        console.error("Error al verificar el estado:", error)
      })
  }
  
  getStatusClass(status) {
    const baseClass = "px-2 inline-flex text-xs leading-5 font-semibold rounded-full "
    
    switch (status) {
      case "completed":
        return baseClass + "bg-green-100 text-green-800"
      case "failed":
        return baseClass + "bg-red-100 text-red-800"
      case "processing":
        return baseClass + "bg-yellow-100 text-yellow-800"
      case "queued":
        return baseClass + "bg-blue-100 text-blue-800"
      default:
        return baseClass + "bg-gray-100 text-gray-800"
    }
  }
}