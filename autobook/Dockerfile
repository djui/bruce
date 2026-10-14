# Long-running service for a VPS or Fly.io. Node runs the TypeScript sources directly (type stripping).
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production \
    AUTOBOOK_STATE=/data/autobook-state.json
COPY package.json ./
COPY src ./src
RUN mkdir -p /data && chown node:node /data
USER node
VOLUME ["/data"]
# Rules: mount a file and set AUTOBOOK_CONFIG_FILE, or pass the JSON in AUTOBOOK_CONFIG.
CMD ["node", "src/node/cli.ts", "run"]
