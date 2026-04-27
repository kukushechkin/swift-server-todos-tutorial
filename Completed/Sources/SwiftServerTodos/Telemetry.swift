import Configuration
import Foundation
import GRPC
import Logging
import Metrics
import NIOCore
import OTelSwiftTracing
import OpenTelemetryApi
import OpenTelemetryProtocolExporterGrpc
import OpenTelemetrySdk
import ServiceLifecycle
import SwiftMetricsShim
import SystemMetrics
import Tracing
import Vapor

func configureTelemetry(_ config: ConfigReader) async throws -> (Logging.Logger, some Service, any MetricsFactory) {
    // Logs stay in the console — configure the Vapor console logger.
    let level =
        config.scoped(to: "log")
        .string(forKey: "level")
        .flatMap { Logger.Level.init(rawValue: $0) } ?? .info
    LoggingSystem.bootstrap { label in
        ConsoleLogger(label: label, console: Terminal(), level: level)
    }

    let logger = Logging.Logger(label: "SwiftServerTodos")

    // Parse OTLP gRPC endpoint from configuration.
    let otelConfig = config.scoped(to: "otel").scoped(to: "exporter").scoped(to: "otlp")
    let baseEndpoint = otelConfig.string(forKey: "endpoint", default: "http://localhost:4317")
    let endpointURL = URL(string: baseEndpoint)!
    let host = endpointURL.host() ?? "localhost"
    let port = endpointURL.port ?? 4317

    // Resource identifies this service in telemetry backends.
    let resource = Resource(attributes: [
        "service.name": .string("SwiftServerTodos")
    ])

    // Create a gRPC channel to the OTLP collector.
    let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
    let channel = ClientConnection.insecure(group: group)
        .connect(host: host, port: port)

    // Traces: gRPC OTLP exporter → batch span processor → tracer provider.
    let traceExporter = OtlpTraceExporter(channel: channel)
    let spanProcessor = BatchSpanProcessor(spanExporter: traceExporter)
    let tracerProvider = TracerProviderSdk(
        resource: resource,
        spanProcessors: [spanProcessor]
    )
    OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)

    // Bridge OpenTelemetry tracing into swift-distributed-tracing's InstrumentationSystem
    // so Vapor's TracingMiddleware creates OTel spans.
    InstrumentationSystem.bootstrap(
        OTelTracer(
            tracerProvider: tracerProvider,
            instrumentationName: "SwiftServerTodos"
        )
    )

    // Metrics: gRPC OTLP exporter → periodic reader → meter provider.
    let metricExporter = OtlpMetricExporter(channel: channel)
    let metricReader = PeriodicMetricReaderBuilder(exporter: metricExporter).build()
    let meterProvider = MeterProviderSdk.builder()
        .setResource(resource: resource)
        .registerMetricReader(reader: metricReader)
        .registerView(
            selector: InstrumentSelector.builder().setInstrument(name: ".*").build(),
            view: View.builder().build()
        )
        .build()

    // Bridge swift-metrics to OpenTelemetry so SystemMetrics flows through OTLP.
    let otelMeter = meterProvider.get(name: "SwiftServerTodos")
    let metricsFactory = OpenTelemetrySwiftMetrics(meter: otelMeter)

    OpenTelemetry.registerMeterProvider(meterProvider: meterProvider)

    // Collect system-level metrics (CPU, memory, file descriptors, etc.).
    let systemMetricsMonitor = SystemMetricsMonitor(
        metricsFactory: metricsFactory,
        logger: logger
    )

    // Lifecycle service that flushes and shuts down OTel providers on graceful shutdown.
    let otelService = OTelLifecycleService(
        tracerProvider: tracerProvider,
        meterProvider: meterProvider,
        eventLoopGroup: group
    )

    let telemetryService = ServiceGroup(
        services: [
            otelService,
            systemMetricsMonitor,
        ],
        logger: logger
    )

    return (logger, telemetryService, metricsFactory)
}

// MARK: - Lifecycle

final class OTelLifecycleService: Service, @unchecked Sendable {
    let tracerProvider: TracerProviderSdk
    let meterProvider: MeterProviderSdk
    let eventLoopGroup: EventLoopGroup

    init(tracerProvider: TracerProviderSdk, meterProvider: MeterProviderSdk, eventLoopGroup: EventLoopGroup) {
        self.tracerProvider = tracerProvider
        self.meterProvider = meterProvider
        self.eventLoopGroup = eventLoopGroup
    }

    func run() async throws {
        try await withGracefulShutdownHandler {
            try await Task.sleep(for: .seconds(365 * 24 * 3600))
        } onGracefulShutdown: {
            self.tracerProvider.forceFlush()
            self.tracerProvider.shutdown()
            _ = self.meterProvider.forceFlush()
            _ = self.meterProvider.shutdown()
            try? self.eventLoopGroup.syncShutdownGracefully()
        }
    }
}

// MARK: - Request logger

extension Logging.Logger {
    @TaskLocal
    static var _current: Logging.Logger?

    static var current: Logging.Logger {
        get throws {
            guard let _current else {
                struct NoCurrentLoggerError: Error {}
                throw NoCurrentLoggerError()
            }
            return _current
        }
    }
}

struct RequestLoggerInjectionMiddleware: Vapor.AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        try await Logger.$_current.withValue(request.logger) {
            try await next.respond(to: request)
        }
    }
}
