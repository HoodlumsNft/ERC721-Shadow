FROM node:20-alpine

WORKDIR /app

# Install pnpm with corepack (ensures compatible version)
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy package files
COPY package.json pnpm-lock.yaml ./

# Install dependencies
RUN pnpm install --no-frozen-lockfile

# Copy source files
COPY *.js ./
COPY README.md ./

# Create non-root user for security
RUN addgroup -g 1001 -S oracle && \
    adduser -S oracle -u 1001 -G oracle && \
    chown -R oracle:oracle /app

USER oracle

# Default command runs the live listener
CMD ["node", "index.js"]
