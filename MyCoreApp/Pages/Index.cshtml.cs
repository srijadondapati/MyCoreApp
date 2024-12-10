using Microsoft.AspNetCore.Mvc.RazorPages;
using System;

namespace MyCoreApp.Pages
{
    public class IndexModel : PageModel
    {
        // Declare properties as public so they can be accessed in the Razor page
        public string BirthdayPerson { get; set; }
        public string Venue { get; set; }
        public string SpecialGuest { get; set; }
        public DateTime EventDate { get; set; }

        // Initialize properties in the constructor to avoid nullable warnings
        public IndexModel()
        {
            BirthdayPerson = string.Empty;
            Venue = string.Empty;
            SpecialGuest = string.Empty;
            EventDate = DateTime.MinValue;
        }

        // Use OnGet method to set default values for properties
        public void OnGet()
        {
            BirthdayPerson = "Mardhal";
            Venue = "Tatipaka";
            SpecialGuest = "Rahul Dondapati";
            EventDate = new DateTime(2024, 12, 28);
        }
    }
}
