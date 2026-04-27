// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "swift-server-todos",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Server scaffolding
        .package(url: "https://github.com/vapor/vapor", from: "4.0.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-configuration", from: "1.2.0"),

        // Telemetry — API
        .package(url: "https://github.com/apple/swift-log", from: "1.5.2"),
        .package(url: "https://github.com/apple/swift-metrics", from: "2.5.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-system-metrics", from: "1.2.1"),

        // Telemetry — OpenTelemetry

        // .package(url: "https://github.com/open-telemetry/opentelemetry-swift", from: "2.2.0"),
        // Custom branch with swift-distributed-tracing support
        .package(url: "https://github.com/simonbility/opentelemetry-swift", branch: "bridge-swift-distributed-tracing"),

        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.2.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),

        // Database
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftServerTodos",
            dependencies: [
                // Server scaffolding
                .product(name: "Vapor", package: "vapor"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "Configuration", package: "swift-configuration"),

                // Telemetry
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
                .product(name: "OpenTelemetryProtocolExporter", package: "opentelemetry-swift"),
                .product(name: "OTelSwiftTracing", package: "opentelemetry-swift"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "SwiftMetricsShim", package: "opentelemetry-swift"),
                .product(name: "SystemMetrics", package: "swift-system-metrics"),

                // Database
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
