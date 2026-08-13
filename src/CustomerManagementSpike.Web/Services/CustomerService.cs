using CustomerManagementSpike.Web.Models;
using System.Collections.Concurrent;

namespace CustomerManagementSpike.Web.Services
{
    public class CustomerService : ICustomerService
    {
        private readonly ConcurrentDictionary<int, Customer> _customers = new();
        private int _nextId = 1;
        private readonly object _idLock = new();

        public CustomerService()
        {
        }

        public IEnumerable<Customer> GetAll()
        {
            return _customers.Values.OrderByDescending(c => c.Id).ToList();
        }

        public Customer? GetById(int id)
        {
            _customers.TryGetValue(id, out var customer);
            return customer;
        }

        public Customer Add(Customer customer)
        {
            lock (_idLock)
            {
                customer.Id = _nextId++;
            }
            _customers[customer.Id] = customer;
            return customer;
        }

        public Customer? Update(Customer customer)
        {
            if (!_customers.ContainsKey(customer.Id))
            {
                return null;
            }
            _customers[customer.Id] = customer;
            return customer;
        }

        public bool Delete(int id)
        {
            return _customers.TryRemove(id, out _);
        }
    }
}
