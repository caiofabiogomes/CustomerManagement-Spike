using System.Text;
using CustomerManagementSpike.MonitoringService.Configuration;
using CustomerManagementSpike.MonitoringService.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CustomerManagementSpike.MonitoringService.Services;

/// <summary>
/// Logs HTTP codes, messages, and service actions directly to a text log file located in the executable folder.
/// </summary>
public class IisStatusFileLogger : IIisStatusFileLogger
{
    private readonly MonitoringOptions _options;
    private readonly ILogger<IisStatusFileLogger> _logger;
    private readonly SemaphoreSlim _lock = new(1, 1);
    private readonly string _logFilePath;

    public IisStatusFileLogger(
        IOptions<MonitoringOptions> options,
        ILogger<IisStatusFileLogger> logger,
        string? customDirectory = null)
    {
        _options = options?.Value ?? throw new ArgumentNullException(nameof(options));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));

        // Use AppContext.BaseDirectory (the executable folder) by default
        var baseDir = customDirectory ?? AppContext.BaseDirectory;
        _logFilePath = Path.Combine(baseDir, _options.LogFileName);
    }

    public string LogFilePath => _logFilePath;

    public async Task LogCheckResultAsync(
        IisCheckResult result,
        bool isStoppingService,
        CancellationToken cancellationToken = default)
    {
        var timestamp = result.Timestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss.fff zzz");
        var codeDisplay = result.StatusCode.HasValue ? result.StatusCode.Value.ToString() : "N/A";
        var statusLabel = result.IsSuccess ? "OK" : "FAILED";
        var actionLabel = isStoppingService ? " [ACTION: Service Stopping]" : string.Empty;

        var logLine = $"[{timestamp}] Status: {statusLabel} | HTTP Code: {codeDisplay} | Message: {result.Message}{actionLabel}{Environment.NewLine}";

        await AppendToFileAsync(logLine, cancellationToken);
    }

    public async Task LogEventAsync(string eventName, string message, CancellationToken cancellationToken = default)
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff zzz");
        var logLine = $"[{timestamp}] EVENT: {eventName} | Details: {message}{Environment.NewLine}";

        await AppendToFileAsync(logLine, cancellationToken);
    }

    private async Task AppendToFileAsync(string content, CancellationToken cancellationToken)
    {
        await _lock.WaitAsync(cancellationToken);
        try
        {
            var directory = Path.GetDirectoryName(_logFilePath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            await File.AppendAllTextAsync(_logFilePath, content, Encoding.UTF8, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write log entry to file: {FilePath}", _logFilePath);
        }
        finally
        {
            _lock.Release();
        }
    }
}
