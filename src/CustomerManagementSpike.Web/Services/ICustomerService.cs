using CustomerManagementSpike.Web.Models;

namespace CustomerManagementSpike.Web.Services
{
    public interface ICustomerService
    {
        IEnumerable<Customer> GetAll();
        Customer? GetById(int id);
        Customer Add(Customer customer);
        Customer? Update(Customer customer);
        bool Delete(int id);
    }
}
