FROM alpine:latest

# Set working directory
WORKDIR /app

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    unzip

# Download and install v2ray v5.7.0
RUN wget https://github.com/v2fly/v2ray-core/releases/download/v5.7.0/v2ray-linux-64.zip && \
    unzip v2ray-linux-64.zip && \
    rm v2ray-linux-64.zip && \
    chmod +x v2ray

# Copy config file
COPY config.json .

# Expose port (Cloud Run requires this)
EXPOSE 8080

# Start v2ray on port 8080
CMD ["./v2ray", "run", "-c", "config.json"]
