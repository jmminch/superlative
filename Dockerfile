# Use a pinned modern SDK. The `stable` tag may resolve to old images in some
# registries/mirrors.
FROM dart:3.9.4 AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Build minimal serving image from AOT-compiled binary
# and the pre-built AOT runtime in the `/runtime/` directory of the base image.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/
COPY --from=build /app/web/ /app/web/
COPY --from=build /app/data/superlatives.yaml /app/data/

# Start server.
EXPOSE 36912
WORKDIR /app
ENV LISTENIP=0.0.0.0
CMD ["/app/bin/server"]
