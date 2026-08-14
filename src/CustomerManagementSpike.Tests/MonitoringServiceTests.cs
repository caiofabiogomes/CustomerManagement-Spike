using System.Net;
using CustomerManagementSpike.MonitoringService;
using CustomerManagementSpike.MonitoringService.Configuration;
using CustomerManagementSpike.MonitoringService.Models;
using CustomerManagementSpike.MonitoringService.Services;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace CustomerManagementSpike.Tests;

public class MonitoringServiceTests : IDisposable
{
    private readonly string _tempTestDir;

    public MonitoringServiceTests()
    {
        _tempTestDir = Path.Combine(Path.GetTempPath(), "MonitoringServiceTests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_tempTestDir);
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_tempTestDir))
            {
                Directory.Delete(_tempTestDir, true);
            }
        }
        catch
        {
            // Ignore cleanup failures in test teardown
        }
    }

    #region Health Checker Tests

    [Fact]
    public async Task CheckStatusAsync_WhenWebsiteReturns200_ReturnsSuccess()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(new HttpResponseMessage(HttpStatusCode.OK)
        {
            ReasonPhrase = "OK"
        });
        var httpClient = new HttpClient(handler);
        var options = Options.Create(new MonitoringOptions
        {
            WebsiteUrl = "http://localhost/",
            CheckIntervalSeconds = 60
        });
        var checker = new IisHealthChecker(httpClient, options, NullLogger<IisHealthChecker>.Instance);

        // Act
        var result = await checker.CheckStatusAsync();

        // Assert
        Assert.True(result.IsSuccess);
        Assert.Equal(200, result.StatusCode);
        Assert.Equal("OK", result.Message);
        Assert.Null(result.Exception);
    }

    [Theory]
    [InlineData(HttpStatusCode.NotFound, "Not Found")]
    [InlineData(HttpStatusCode.InternalServerError, "Internal Server Error")]
    [InlineData(HttpStatusCode.ServiceUnavailable, "Service Unavailable")]
    [InlineData(HttpStatusCode.Unauthorized, "Unauthorized")]
    public async Task CheckStatusAsync_WhenWebsiteReturnsNon200_ReturnsFailureWithStatus(HttpStatusCode statusCode, string reason)
    {
        // Arrange
        var handler = new MockHttpMessageHandler(new HttpResponseMessage(statusCode)
        {
            ReasonPhrase = reason
        });
        var httpClient = new HttpClient(handler);
        var options = Options.Create(new MonitoringOptions
        {
            WebsiteUrl = "http://localhost/",
            CheckIntervalSeconds = 60
        });
        var checker = new IisHealthChecker(httpClient, options, NullLogger<IisHealthChecker>.Instance);

        // Act
        var result = await checker.CheckStatusAsync();

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Equal((int)statusCode, result.StatusCode);
        Assert.Equal(reason, result.Message);
    }

    [Fact]
    public async Task CheckStatusAsync_WhenHttpConnectionFails_ReturnsErrorResult()
    {
        // Arrange
        var handler = new MockHttpMessageHandler(_ => throw new HttpRequestException("No connection could be made because the target machine actively refused it"));
        var httpClient = new HttpClient(handler);
        var options = Options.Create(new MonitoringOptions
        {
            WebsiteUrl = "http://localhost:9999/",
            CheckIntervalSeconds = 60
        });
        var checker = new IisHealthChecker(httpClient, options, NullLogger<IisHealthChecker>.Instance);

        // Act
        var result = await checker.CheckStatusAsync();

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Null(result.StatusCode);
        Assert.Contains("HTTP connection error", result.Message);
        Assert.NotNull(result.Exception);
    }

    #endregion

    #region File Logger Tests

    [Fact]
    public async Task LogCheckResultAsync_When200Ok_WritesFormattedEntryToFile()
    {
        // Arrange
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "test_monitor.log"
        });
        var logger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);

        var result = IisCheckResult.Success(HttpStatusCode.OK, "OK");

        // Act
        await logger.LogCheckResultAsync(result, isStoppingService: false);

        // Assert
        Assert.True(File.Exists(logger.LogFilePath));
        var logContent = await File.ReadAllTextAsync(logger.LogFilePath);
        Assert.Contains("Status: OK", logContent);
        Assert.Contains("HTTP Code: 200", logContent);
        Assert.Contains("Message: OK", logContent);
        Assert.DoesNotContain("[ACTION: Service Stopping]", logContent);
    }

    [Fact]
    public async Task LogCheckResultAsync_WhenFailureAndStopping_WritesStoppingActionToFile()
    {
        // Arrange
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "test_monitor_fail.log"
        });
        var logger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);

        var result = IisCheckResult.Failure(HttpStatusCode.InternalServerError, "Internal Server Error");

        // Act
        await logger.LogCheckResultAsync(result, isStoppingService: true);

        // Assert
        Assert.True(File.Exists(logger.LogFilePath));
        var logContent = await File.ReadAllTextAsync(logger.LogFilePath);
        Assert.Contains("Status: FAILED", logContent);
        Assert.Contains("HTTP Code: 500", logContent);
        Assert.Contains("Message: Internal Server Error", logContent);
        Assert.Contains("[ACTION: Service Stopping]", logContent);
    }

    [Fact]
    public async Task LogEventAsync_WritesServiceLifecycleEvents()
    {
        // Arrange
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "events.log"
        });
        var logger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);

        // Act
        await logger.LogEventAsync("SERVICE_START", "Service initialized successfully.");

        // Assert
        var logContent = await File.ReadAllTextAsync(logger.LogFilePath);
        Assert.Contains("EVENT: SERVICE_START", logContent);
        Assert.Contains("Service initialized successfully.", logContent);
    }

    #endregion

    #region Monitoring Worker Lifecycle & Stopping Tests

    [Fact]
    public async Task RunSingleCheckAsync_WhenStatusIs200_DoesNotStopApplication()
    {
        // Arrange
        var mockChecker = new FakeHealthChecker(IisCheckResult.Success(HttpStatusCode.OK, "OK"));
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "worker_200.log",
            StopOnNon200 = true
        });
        var fileLogger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);
        var mockLifetime = new FakeHostApplicationLifetime();

        var worker = new IisMonitoringWorker(
            mockChecker,
            fileLogger,
            mockLifetime,
            options,
            NullLogger<IisMonitoringWorker>.Instance);

        // Act
        var continueRunning = await worker.RunSingleCheckAsync();

        // Assert
        Assert.True(continueRunning);
        Assert.False(mockLifetime.StopApplicationCalled);

        var logContent = await File.ReadAllTextAsync(fileLogger.LogFilePath);
        Assert.Contains("HTTP Code: 200", logContent);
    }

    [Fact]
    public async Task RunSingleCheckAsync_WhenStatusIsNon200_CallsStopApplicationAndReturnsFalse()
    {
        // Arrange
        var mockChecker = new FakeHealthChecker(IisCheckResult.Failure(HttpStatusCode.ServiceUnavailable, "Service Unavailable"));
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "worker_503.log",
            StopOnNon200 = true
        });
        var fileLogger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);
        var mockLifetime = new FakeHostApplicationLifetime();

        var exitCode = 0;
        var worker = new IisMonitoringWorker(
            mockChecker,
            fileLogger,
            mockLifetime,
            options,
            NullLogger<IisMonitoringWorker>.Instance,
            code => exitCode = code);

        // Act
        var continueRunning = await worker.RunSingleCheckAsync();

        // Assert
        Assert.False(continueRunning);
        Assert.Equal(1, exitCode);

        var logContent = await File.ReadAllTextAsync(fileLogger.LogFilePath);
        Assert.Contains("HTTP Code: 503", logContent);
        Assert.Contains("[ACTION: Service Stopping]", logContent);
    }

    [Fact]
    public async Task RunSingleCheckAsync_WhenConnectionFails_CallsStopApplicationAndReturnsFalse()
    {
        // Arrange
        var mockChecker = new FakeHealthChecker(IisCheckResult.Error("HTTP connection refused"));
        var options = Options.Create(new MonitoringOptions
        {
            LogFileName = "worker_conn_err.log",
            StopOnNon200 = true
        });
        var fileLogger = new IisStatusFileLogger(options, NullLogger<IisStatusFileLogger>.Instance, _tempTestDir);
        var mockLifetime = new FakeHostApplicationLifetime();

        var exitCode = 0;
        var worker = new IisMonitoringWorker(
            mockChecker,
            fileLogger,
            mockLifetime,
            options,
            NullLogger<IisMonitoringWorker>.Instance,
            code => exitCode = code);

        // Act
        var continueRunning = await worker.RunSingleCheckAsync();

        // Assert
        Assert.False(continueRunning);
        Assert.Equal(1, exitCode);

        var logContent = await File.ReadAllTextAsync(fileLogger.LogFilePath);
        Assert.Contains("Status: FAILED", logContent);
        Assert.Contains("HTTP connection refused", logContent);
        Assert.Contains("[ACTION: Service Stopping]", logContent);
    }

    #endregion

    #region Test Helper Fakes

    private class MockHttpMessageHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _responseFactory;

        public MockHttpMessageHandler(HttpResponseMessage response)
        {
            _responseFactory = _ => response;
        }

        public MockHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
        {
            _responseFactory = responseFactory;
        }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return Task.FromResult(_responseFactory(request));
        }
    }

    private class FakeHealthChecker : IIisHealthChecker
    {
        private readonly IisCheckResult _result;

        public FakeHealthChecker(IisCheckResult result)
        {
            _result = result;
        }

        public Task<IisCheckResult> CheckStatusAsync(CancellationToken cancellationToken = default)
        {
            return Task.FromResult(_result);
        }
    }

    private class FakeHostApplicationLifetime : IHostApplicationLifetime
    {
        public bool StopApplicationCalled { get; private set; }
        private readonly CancellationTokenSource _cts = new();

        public CancellationToken ApplicationStarted => _cts.Token;
        public CancellationToken ApplicationStopping => _cts.Token;
        public CancellationToken ApplicationStopped => _cts.Token;

        public void StopApplication()
        {
            StopApplicationCalled = true;
            _cts.Cancel();
        }
    }

    #endregion
}
