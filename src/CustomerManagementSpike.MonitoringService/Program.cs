using CustomerManagementSpike.MonitoringService;
using CustomerManagementSpike.MonitoringService.Configuration;
using CustomerManagementSpike.MonitoringService.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

var builder = Host.CreateApplicationBuilder(args);

// Enable running as a native Windows Service
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "CustomerSpikeIisMonitor";
});

// Configure Options
builder.Services.Configure<MonitoringOptions>(
    builder.Configuration.GetSection(MonitoringOptions.SectionName));

var monitoringConfig = builder.Configuration
    .GetSection(MonitoringOptions.SectionName)
    .Get<MonitoringOptions>() ?? new MonitoringOptions();

// Configure HttpClient for health checking
builder.Services.AddHttpClient<IIisHealthChecker, IisHealthChecker>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(Math.Max(5, monitoringConfig.RequestTimeoutSeconds));
    client.DefaultRequestHeaders.Add("User-Agent", "CustomerSpike-IisMonitor-WindowsService/1.0");
});

// Register file logger and monitoring worker
builder.Services.AddSingleton<IIisStatusFileLogger, IisStatusFileLogger>();
builder.Services.AddHostedService<IisMonitoringWorker>();

var host = builder.Build();
host.Run();
