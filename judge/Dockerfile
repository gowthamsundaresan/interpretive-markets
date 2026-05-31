FROM --platform=linux/amd64 node:22-alpine

WORKDIR /app

# Vendor the shared package and symlink it as the workspace dep the judge imports.
COPY interpretive-markets-backend/packages/shared /shared
RUN mkdir -p /app/node_modules/@interpretive && ln -sfn /shared /app/node_modules/@interpretive/shared

# Install judge deps (skip the postinstall link-shared script; we vendored manually).
COPY interpretive-markets/judge/package.json interpretive-markets/judge/package-lock.json* ./
RUN npm install --ignore-scripts

# Judge source + the contract deployment record (read at runtime via DEPLOYMENT_FILE).
COPY interpretive-markets/judge/ ./
COPY interpretive-markets/script/outputs/sepolia/deployment.json ./deployment.json

EXPOSE 3001
CMD ["npx", "tsx", "src/index.ts"]
