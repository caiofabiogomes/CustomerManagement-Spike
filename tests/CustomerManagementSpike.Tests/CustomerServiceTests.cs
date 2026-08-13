using CustomerManagementSpike.Web.Models;
using CustomerManagementSpike.Web.Services;
using Xunit;

namespace CustomerManagementSpike.Tests
{
    public class CustomerServiceTests
    {
        private readonly CustomerService _customerService;

        public CustomerServiceTests()
        {
            _customerService = new CustomerService();
        }

        [Fact]
        public void Add_ShouldAssignIncrementalIdAndStoreCustomer()
        {
            // Arrange
            var customer = new Customer
            {
                Name = "John Doe",
                Email = "john.doe@example.com",
                Phone = "123-456-7890"
            };

            // Act
            var addedCustomer = _customerService.Add(customer);

            // Assert
            Assert.Equal(1, addedCustomer.Id);
            Assert.Equal("John Doe", addedCustomer.Name);

            var retrieved = _customerService.GetById(addedCustomer.Id);
            Assert.NotNull(retrieved);
            Assert.Equal("john.doe@example.com", retrieved.Email);
        }

        [Fact]
        public void GetAll_ShouldReturnAllCustomers()
        {
            // Arrange
            _customerService.Add(new Customer { Name = "Alice", Email = "alice@example.com", Phone = "111-222-3333" });
            _customerService.Add(new Customer { Name = "Bob", Email = "bob@example.com", Phone = "444-555-6666" });

            // Act
            var customers = _customerService.GetAll().ToList();

            // Assert
            Assert.Equal(2, customers.Count);
        }

        [Fact]
        public void Update_ShouldModifyExistingCustomer()
        {
            // Arrange
            var original = _customerService.Add(new Customer { Name = "Charlie", Email = "charlie@old.com", Phone = "555-1234" });

            // Act
            original.Email = "charlie@new.com";
            var updated = _customerService.Update(original);

            // Assert
            Assert.NotNull(updated);
            Assert.Equal("charlie@new.com", updated.Email);
        }

        [Fact]
        public void Delete_ShouldRemoveCustomer()
        {
            // Arrange
            var customer = _customerService.Add(new Customer { Name = "Dave", Email = "dave@example.com", Phone = "555-9999" });

            // Act
            var deleteResult = _customerService.Delete(customer.Id);

            // Assert
            Assert.True(deleteResult);
            Assert.Null(_customerService.GetById(customer.Id));
        }
    }
}
