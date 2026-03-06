#!/bin/bash
set -e

# Run migrations
bin/weather_edge eval "WeatherEdge.Release.migrate"

# Start the server
exec bin/weather_edge start
