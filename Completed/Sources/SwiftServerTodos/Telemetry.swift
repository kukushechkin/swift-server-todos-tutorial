import Configuration
import Foundation
import Logging
import Metrics
import OTel
import ServiceLifecycle
import SystemMetrics
import Tracing
import Vapor

func configureTelemetry(_ config: ConfigReader) async throws -> (Logger, some Service) {
    let level =
        config.scoped(to: "log")
        .string(forKey: "level")
        .flatMap { Logger.Level.init(rawValue: $0) } ?? .info

    // Logs, metrics, and traces are exported via OpenTelemetry (OTLP).
    // The OTel diagnostic logger is left as default (stderr) so OTel's own
    // internal logs don't recurse back through the multiplexed handler below.
    var otelConfig = OTel.Configuration.default
    otelConfig.serviceName = "SwiftServerTodos"

    // Create the OTel backends.
    let otelLoggingBackend = try OTel.makeLoggingBackend(configuration: otelConfig)
    let otelMetricsBackend = try OTel.makeMetricsBackend(configuration: otelConfig)
    let otelTracingBackend = try OTel.makeTracingBackend(configuration: otelConfig)

    // Fan logs out to both the Vapor console logger and the OTel exporter.
    // The OTel metadata provider attaches `trace_id` and `span_id` from the
    // active span, so logs emitted during a traced request can be correlated
    // with their trace in Grafana.
    @Sendable
    func multiplexLogHandler(label: String, metadataProvider: Logger.MetadataProvider) -> MultiplexLogHandler {
        MultiplexLogHandler(
            [
                ConsoleLogger(label: label, console: Terminal(), level: level),
                otelLoggingBackend.factory(label),
            ],
            metadataProvider: metadataProvider
        )
    }

    // Bootstrap the global logging system too, as a fallback for any `Logger`
    // created without going through the root logger below (for example, by
    // third-party code). Tag those log lines `scope: global` so they're easy
    // to tell apart from the ones that flow through the task-local root logger.
    let otelMetadataProvider = OTel.makeLoggingMetadataProvider()
    let globalMetadataProvider = Logger.MetadataProvider {
        var metadata = otelMetadataProvider.get()
        metadata["scope"] = "global"
        return metadata
    }
    LoggingSystem.bootstrap { label in
        multiplexLogHandler(label: label, metadataProvider: globalMetadataProvider)
    }

    MetricsSystem.bootstrap(otelMetricsBackend.factory)
    InstrumentationSystem.bootstrap(otelTracingBackend.factory)

    let logger = Logger(
        label: "SwiftServerTodos",
        factory: { label in multiplexLogHandler(label: label, metadataProvider: otelMetadataProvider) }
    )

    // Collect system-level metrics (CPU, memory, file descriptors, etc.).
    let systemMetricsMonitor = SystemMetricsMonitor(
        metricsFactory: otelMetricsBackend.factory,
        logger: logger
    )

    // Combine all OTel services so they start and stop together.
    let telemetryService = ServiceGroup(
        services: [
            otelLoggingBackend.service,
            otelMetricsBackend.service,
            otelTracingBackend.service,
            systemMetricsMonitor,
        ]
    )

    return (logger, telemetryService)
}

struct RequestLoggerInjectionMiddleware: Vapor.AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        try await withLogger(request.logger) { _ in
            try await next.respond(to: request)
        }
    }
}
