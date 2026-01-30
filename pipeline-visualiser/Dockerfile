FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
    build-base \
    git \
    && rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /app

# Copy Gemfile first
COPY Gemfile ./

# Remove lockfile and regenerate with current Ruby/Bundler
RUN bundle install --without development test

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001 -G appuser

# Create writable directories for readonly root filesystem
RUN mkdir -p /tmp /var/tmp && \
    chown -R appuser:appuser /app /tmp /var/tmp

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 4567

# Start the application
CMD ["ruby", "index.rb", "-o", "0.0.0.0"]
