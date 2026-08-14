namespace CustomerManagementSpike.MonitoringService.Configuration;

/// <summary>
/// Configuration options for the IIS Website Monitoring Windows Service.
/// </summary>
public class MonitoringOptions
{
    public const string SectionName = "Monitoring";

    /// <summary>
    /// The target IIS website URL to monitor (e.g., http://localhost/ or http://localhost:80).
    /// </summary>
    public string WebsiteUrl { get; set; } = "http://localhost/";

    /// <summary>
    /// Interval in seconds between website health checks (defaults to 60 seconds).
    /// </summary>
    public int CheckIntervalSeconds { get; set; } = 60;

    /// <summary>
    /// HTTP request timeout in seconds.
    /// </summary>
    public int RequestTimeoutSeconds { get; set; } = 15;

    /// <summary>
    /// Log file name saved in the executable directory.
    /// </summary>
    public string LogFileName { get; set; } = "iis_monitor.log";

    /// <summary>
    /// Whether to stop the Windows service if the HTTP response is different from 200 (OK).
    /// </summary>
    public bool StopOnNon200 { get; set; } = true;
}
