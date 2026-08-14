using CustomerManagementSpike.MonitoringService.Models;

namespace CustomerManagementSpike.MonitoringService.Services;

/// <summary>
/// Writes IIS monitoring results and lifecycle events to a log file in the executable's directory.
/// </summary>
public interface IIisStatusFileLogger
{
    /// <summary>
    /// Gets the absolute path of the output log file.
    /// </summary>
    string LogFilePath { get; }

    /// <summary>
    /// Appends the IIS health check result (HTTP Code and message) to the log file.
    /// </summary>
    /// <param name="result">The IIS check result.</param>
    /// <param name="isStoppingService">Whether the service is stopping as a consequence of this check.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task LogCheckResultAsync(IisCheckResult result, bool isStoppingService, CancellationToken cancellationToken = default);

    /// <summary>
    /// Appends a general service lifecycle event (e.g., Started, Stopped) to the log file.
    /// </summary>
    /// <param name="eventName">Name of the event.</param>
    /// <param name="message">Message details.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task LogEventAsync(string eventName, string message, CancellationToken cancellationToken = default);
}
