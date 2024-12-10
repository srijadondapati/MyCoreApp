let voteCount = 0;

function vote() {
    // Increment the vote count and update the display
    voteCount++;
    document.getElementById('vote-count').innerHTML = `Count: ${voteCount}`;

    // Change the button to show it's been clicked
    alert("Thank you for voting! We appreciate your response.");
    document.getElementById('coming-button').innerHTML = "Coming!";
    document.getElementById('coming-button').style.backgroundColor = "#ddd";
    document.getElementById('coming-button').style.color = "#333";
    document.getElementById('coming-button').style.cursor = "not-allowed";
    document.getElementById('coming-button').disabled = true;
}
