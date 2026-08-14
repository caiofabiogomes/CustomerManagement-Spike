using CustomerManagementSpike.MonitoringService.Models;

namespace CustomerManagementSpike.MonitoringService.Services;

/// <summary>
/// Probes the IIS website to verify its HTTP response status.
/// </summary>
public interface IIisHealthChecker
{
    /// <summary>
    /// Checks the configured IIS website status asynchronously.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Result containing HTTP status code, message, and success flag.</returns>
    Task<IisCheckResult> CheckStatusAsync(CancellationToken cancellationToken = default);
}
