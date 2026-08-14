using CustomerManagementSpike.Web.Services;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.DataProtection;

var builder = WebApplication.CreateBuilder(args);


var dataProtectionKeysDir = Path.Combine(builder.Environment.ContentRootPath, "App_Data", "DataProtection-Keys");
builder.Services.AddDataProtection()
    .SetApplicationName("CustomerManagementSpike")
    .PersistKeysToFileSystem(new DirectoryInfo(dataProtectionKeysDir));


builder.Services.AddAntiforgery(options =>
{
    options.Cookie.Name = ".CustomerManagementSpike.Antiforgery";
    options.Cookie.Path = "/";
    options.Cookie.SameSite = SameSiteMode.Lax;
    options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
});

// Add services to the container.
builder.Services.AddControllersWithViews();
builder.Services.AddSingleton<ICustomerService, CustomerService>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseRouting();

app.UseAuthorization();

app.MapStaticAssets();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Customers}/{action=Index}/{id?}")
    .WithStaticAssets();

app.Run();
