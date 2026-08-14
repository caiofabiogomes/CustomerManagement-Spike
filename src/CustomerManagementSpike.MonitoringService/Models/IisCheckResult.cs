using System.Net;

namespace CustomerManagementSpike.MonitoringService.Models;

/// <summary>
/// Represents the result of an IIS website health check.
/// </summary>
public record IisCheckResult(
    int? StatusCode,
    string Message,
    bool IsSuccess,
    DateTime Timestamp,
    Exception? Exception = null)
{
    public static IisCheckResult Success(HttpStatusCode statusCode, string reasonPhrase) =>
        new((int)statusCode, reasonPhrase, true, DateTime.UtcNow);

    public static IisCheckResult Failure(HttpStatusCode statusCode, string reasonPhrase) =>
        new((int)statusCode, reasonPhrase, false, DateTime.UtcNow);

    public static IisCheckResult Error(string errorMessage, Exception? ex = null) =>
        new(null, errorMessage, false, DateTime.UtcNow, ex);
}
