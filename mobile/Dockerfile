# ==========================================
# Stage 1: Build Flutter Web application
# ==========================================
FROM ubuntu:24.04 AS builder

ARG FLUTTER_VERSION=3.47.5
ARG API_BASE_URL=https://ludo-websocket-backend-7rhnb54xmq-ew.a.run.app/api/v1
ARG WEBSOCKET_URL=wss://ludo-websocket-backend-7rhnb54xmq-ew.a.run.app/ws

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download exact Flutter version
RUN git clone \
    --branch ${FLUTTER_VERSION} \
    --depth 1 \
    https://github.com/flutter/flutter.git \
    ${FLUTTER_HOME}

# Verify Flutter
RUN flutter --version

WORKDIR /app

# Copy dependency files first
COPY pubspec.yaml pubspec.lock ./

# Install Flutter dependencies
RUN flutter pub get

# Copy application source
COPY . .
RUN touch .env

# Build Flutter web application
RUN flutter build web --release \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=WEBSOCKET_URL=${WEBSOCKET_URL}


# ==========================================
# Stage 2: Serve with Nginx
# ==========================================
FROM nginx:alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
