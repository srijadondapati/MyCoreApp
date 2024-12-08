function showAlert(message) {
    const alertBox = document.getElementById('alert-box');
    alertBox.textContent = message;
    alertBox.classList.add('show-alert');
    
    // Auto hide alert after 3 seconds
    setTimeout(() => {
        alertBox.classList.remove('show-alert');
    }, 3000);
}
