FROM --platform=linux/amd64 node:22-alpine

WORKDIR /app

# Install judge deps first so this layer caches.
COPY package.json package-lock.json* ./
RUN npm install --ignore-scripts

# Vendor the shared package straight into node_modules — no symlink — so Node
# ESM resolves @interpretive/shared natively without any loader trickery.
COPY _vendored_shared /app/node_modules/@interpretive/shared

# Judge source + the contract deployment record (read at runtime via DEPLOYMENT_FILE).
COPY . ./

EXPOSE 3001
CMD ["npx", "tsx", "src/index.ts"]
