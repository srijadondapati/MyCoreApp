let voteCount = 0;

function vote() {
    // Increment the vote count and update the display
    voteCount++;
    document.getElementById('vote-count').innerHTML = `Count: ${voteCount}`;

    // Change the button to show it's been clicked
    alert("Thank you for voting! We appreciate your response.");
    const button = document.getElementById('coming-button');
    button.innerHTML = "Coming!";
    button.style.backgroundColor = "#ddd";
    button.style.color = "#333";
    button.style.cursor = "not-allowed";
    button.disabled = true;
}
