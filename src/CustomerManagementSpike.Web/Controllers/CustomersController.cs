using CustomerManagementSpike.Web.Models;
using CustomerManagementSpike.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace CustomerManagementSpike.Web.Controllers
{
    public class CustomersController : Controller
    {
        private readonly ICustomerService _customerService;

        public CustomersController(ICustomerService customerService)
        {
            _customerService = customerService;
        }

        public IActionResult Index()
        {
            var customers = _customerService.GetAll();
            return View(customers);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult Create(Customer customer)
        {
            if (ModelState.IsValid)
            {
                _customerService.Add(customer);
                return RedirectToAction(nameof(Index));
            }

            return View("Index", _customerService.GetAll());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult Edit(Customer customer)
        {
            if (ModelState.IsValid)
            {
                _customerService.Update(customer);
                return RedirectToAction(nameof(Index));
            }

            return View("Index", _customerService.GetAll());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public IActionResult Delete(int id)
        {
            _customerService.Delete(id);
            return RedirectToAction(nameof(Index));
        }
    }
}
