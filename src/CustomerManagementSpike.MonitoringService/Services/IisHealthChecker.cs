using System.Net;
using CustomerManagementSpike.MonitoringService.Configuration;
using CustomerManagementSpike.MonitoringService.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CustomerManagementSpike.MonitoringService.Services;

/// <summary>
/// Probes the IIS website by sending an HTTP request and inspecting the HTTP response code.
/// </summary>
public class IisHealthChecker : IIisHealthChecker
{
    private readonly HttpClient _httpClient;
    private readonly MonitoringOptions _options;
    private readonly ILogger<IisHealthChecker> _logger;

    public IisHealthChecker(
        HttpClient httpClient,
        IOptions<MonitoringOptions> options,
        ILogger<IisHealthChecker> logger)
    {
        _httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
        _options = options?.Value ?? throw new ArgumentNullException(nameof(options));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public async Task<IisCheckResult> CheckStatusAsync(CancellationToken cancellationToken = default)
    {
        var targetUrl = _options.WebsiteUrl;
        _logger.LogDebug("Probing IIS website at {Url}...", targetUrl);

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, targetUrl);
            using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);

            var statusCode = response.StatusCode;
            var reasonPhrase = string.IsNullOrWhiteSpace(response.ReasonPhrase)
                ? statusCode.ToString()
                : response.ReasonPhrase;

            if (statusCode == HttpStatusCode.OK)
            {
                _logger.LogInformation("IIS website returned {StatusCode} ({ReasonPhrase}).", (int)statusCode, reasonPhrase);
                return IisCheckResult.Success(statusCode, reasonPhrase);
            }

            _logger.LogWarning("IIS website returned non-200 status: {StatusCode} ({ReasonPhrase}).", (int)statusCode, reasonPhrase);
            return IisCheckResult.Failure(statusCode, reasonPhrase);
        }
        catch (OperationCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            var msg = $"Request timed out after {_options.RequestTimeoutSeconds} seconds.";
            _logger.LogError(ex, "HTTP timeout while checking {Url}: {Message}", targetUrl, msg);
            return IisCheckResult.Error(msg, ex);
        }
        catch (HttpRequestException ex)
        {
            var msg = $"HTTP connection error: {ex.Message}";
            _logger.LogError(ex, "HTTP error while checking {Url}: {Message}", targetUrl, msg);
            return IisCheckResult.Error(msg, ex);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            var msg = $"Unexpected error checking IIS status: {ex.Message}";
            _logger.LogError(ex, "Unexpected error while probing {Url}: {Message}", targetUrl, msg);
            return IisCheckResult.Error(msg, ex);
        }
    }
}
