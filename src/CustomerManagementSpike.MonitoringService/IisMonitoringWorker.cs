using CustomerManagementSpike.MonitoringService.Configuration;
using CustomerManagementSpike.MonitoringService.Services;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CustomerManagementSpike.MonitoringService;

/// <summary>
/// Background Windows Service worker that monitors an IIS website every 60 seconds (or configured interval).
/// Logs the HTTP code and message to a file in the executable folder.
/// Automatically stops the service if the returned HTTP status is different from 200 (OK).
/// </summary>
public class IisMonitoringWorker : BackgroundService
{
    private readonly IIisHealthChecker _healthChecker;
    private readonly IIisStatusFileLogger _fileLogger;
    private readonly IHostApplicationLifetime _appLifetime;
    private readonly MonitoringOptions _options;
    private readonly ILogger<IisMonitoringWorker> _logger;
    private readonly Action<int> _exitAction;

    public IisMonitoringWorker(
        IIisHealthChecker healthChecker,
        IIisStatusFileLogger fileLogger,
        IHostApplicationLifetime appLifetime,
        IOptions<MonitoringOptions> options,
        ILogger<IisMonitoringWorker> logger,
        Action<int>? exitAction = null)
    {
        _healthChecker = healthChecker ?? throw new ArgumentNullException(nameof(healthChecker));
        _fileLogger = fileLogger ?? throw new ArgumentNullException(nameof(fileLogger));
        _appLifetime = appLifetime ?? throw new ArgumentNullException(nameof(appLifetime));
        _options = options?.Value ?? throw new ArgumentNullException(nameof(options));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _exitAction = exitAction ?? (code => Environment.Exit(code));
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("IIS Monitoring Service is starting. Target URL: {Url}, Interval: {Interval}s, LogFile: {LogFile}",
            _options.WebsiteUrl, _options.CheckIntervalSeconds, _fileLogger.LogFilePath);

        await _fileLogger.LogEventAsync(
            "SERVICE_START",
            $"Started monitoring URL '{_options.WebsiteUrl}' with check interval of {_options.CheckIntervalSeconds}s. Output log: {_fileLogger.LogFilePath}",
            cancellationToken);

        await base.StartAsync(cancellationToken);
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("IIS Monitoring Service is stopping.");

        await _fileLogger.LogEventAsync(
            "SERVICE_STOP",
            "Service stop requested.",
            cancellationToken);

        await base.StopAsync(cancellationToken);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(Math.Max(1, _options.CheckIntervalSeconds));
        _logger.LogInformation("Monitoring loop started with {Interval}s interval.", interval.TotalSeconds);

        // Perform an initial check immediately upon service startup
        if (!await RunSingleCheckAsync(stoppingToken))
        {
            return;
        }

        using var timer = new PeriodicTimer(interval);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken))
                {
                    break;
                }

                var shouldContinue = await RunSingleCheckAsync(stoppingToken);
                if (!shouldContinue)
                {
                    break;
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Normal shutdown requested
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error occurred during monitoring execution loop.");
            }
        }
    }

    /// <summary>
    /// Executes a single health check, writes to the log file, and initiates shutdown if non-200 OK.
    /// </summary>
    /// <returns>True if monitoring should continue; false if the service is stopping.</returns>
    public async Task<bool> RunSingleCheckAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var result = await _healthChecker.CheckStatusAsync(cancellationToken);
            var isOk = result.IsSuccess && result.StatusCode == 200;

            if (isOk)
            {
                _logger.LogInformation("IIS Health Check OK: HTTP {Code} {Message}", result.StatusCode, result.Message);
                await _fileLogger.LogCheckResultAsync(result, isStoppingService: false, cancellationToken);
                return true;
            }

            var stopService = _options.StopOnNon200;
            var codeText = result.StatusCode.HasValue ? result.StatusCode.Value.ToString() : "N/A";

            _logger.LogWarning(
                "IIS Health Check returned non-200 status (Code: {Code}, Message: {Message}). StopOnNon200 is {StopOnNon200}.",
                codeText, result.Message, stopService);

            await _fileLogger.LogCheckResultAsync(result, isStoppingService: stopService, cancellationToken);

            if (stopService)
            {
                _logger.LogCritical("Service is terminating on failure because HTTP response code is not 200 (OK). SCM will auto-recover after 300 seconds.");
                await _fileLogger.LogEventAsync("SERVICE_FAILURE", "Terminating service process with exit code 1 to trigger Windows SCM auto-recovery in 300 seconds.", cancellationToken);
                await Task.Delay(500, CancellationToken.None);
                _exitAction(1);
                return false;
            }

            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Fatal error executing health check.");
            if (_options.StopOnNon200)
            {
                await _fileLogger.LogEventAsync("SERVICE_FAILURE", $"Fatal error: {ex.Message}. Terminating with exit code 1.", CancellationToken.None);
                await Task.Delay(500, CancellationToken.None);
                _exitAction(1);
                return false;
            }
            return true;
        }
    }
}
