FROM --platform=linux/amd64 node:22-alpine AS build

WORKDIR /app

# Copy the shared workspace package first so the symlink resolves at install time.
COPY interpretive-markets-backend/packages/shared /shared
RUN mkdir -p /app/node_modules/@interpretive && ln -sfn /shared /app/node_modules/@interpretive/shared

COPY interpretive-markets/judge/package.json interpretive-markets/judge/package-lock.json* ./
RUN npm install --omit=dev=false

COPY interpretive-markets/judge/ ./
RUN npm run build

FROM --platform=linux/amd64 node:22-alpine
WORKDIR /app

COPY interpretive-markets-backend/packages/shared /shared
RUN mkdir -p /app/node_modules/@interpretive && ln -sfn /shared /app/node_modules/@interpretive/shared

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY interpretive-markets/judge/package.json ./

EXPOSE 3001
CMD ["node", "dist/index.js"]
