using Microsoft.AspNetCore.Mvc.RazorPages;
using System;

namespace MyCoreApp.Pages
{
    public class IndexModel : PageModel
    {
        public string BirthdayPerson { get; set; }
        public string Venue { get; set; }
        public string SpecialGuest { get; set; }
        public DateTime EventDate { get; set; }

        public void OnGet()
        {
            BirthdayPerson = "Mardhal";
            Venue = "Tatipaka";
            SpecialGuest = "Rahul Dondapati";
            EventDate = new DateTime(2024, 12, 28);
        }
    }
}
