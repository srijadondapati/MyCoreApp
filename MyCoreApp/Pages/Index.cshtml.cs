using Microsoft.AspNetCore.Mvc.RazorPages;
using System;

namespace MyCoreApp.Pages
{
    public class IndexModel : PageModel
    {
        // Define public properties
        public string BirthdayPerson { get; set; }
        public string Venue { get; set; }
        public string SpecialGuest { get; set; }
        public DateTime EventDate { get; set; }

        // Initialize the properties in the OnGet method
        public void OnGet()
        {
            // Example values; adjust these as necessary
            BirthdayPerson = "Mardhal";
            Venue = "Tatipaka";
            SpecialGuest = "Rahul Dondapati";
            EventDate = new DateTime(2024, 12, 28);  // Example event date
        }
    }
}
