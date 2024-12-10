using Microsoft.AspNetCore.Mvc.RazorPages;
using System;

namespace MyCoreApp.Pages
{
    public class IndexModel : PageModel
    {
        // Make sure these properties are public
        public string BirthdayPerson { get; set; }
        public string Venue { get; set; }
        public string SpecialGuest { get; set; }
        public DateTime EventDate { get; set; }

        // Initialize the properties in the OnGet method
        public void OnGet()
        {
            // Example values; replace them as per your requirements
            BirthdayPerson = "Mardhal";
            Venue = "Tatipaka";
            SpecialGuest = "Rahul Dondapati";
            EventDate = new DateTime(2024, 12, 28);
        }
    }
}
