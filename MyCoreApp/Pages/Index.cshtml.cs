using Microsoft.AspNetCore.Mvc.RazorPages;
using System;

namespace MyCoreApp.Pages
{
    public class IndexModel : PageModel
    {
        // Ensure all properties are public and accessible in the Razor page
        public string BirthdayPerson { get; set; }
        public string Venue { get; set; }
        public string SpecialGuest { get; set; }
        public DateTime EventDate { get; set; }

        // OnGet method to set default values
        public void OnGet()
        {
            // Initialize properties here
            BirthdayPerson = "Mardhal";
            Venue = "Tatipaka";
            SpecialGuest = "Rahul Dondapati";
            EventDate = new DateTime(2024, 12, 28);
        }
    }
}
