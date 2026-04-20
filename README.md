# Universal-Vehicle-Telemetry

The Universal Vehicle Telemetry Simulator is a production-ready, distributed system designed to simulate and visualize high-fidelity vehicle telemetry across multiple transit modes (Cars, Trains, Planes, etc.).

Built with a decoupled architecture, it leverages a C++ backend for highly concurrent, thread-safe state management, a Python simulator that dynamically calculates routes and physical constraints (speed limits, battery drain, thermal lag) using OpenRouteService and HERE Transit APIs, and a Qt6/QML frontend that provides a real-time, data-driven UI with robust anti-race-condition guards.
