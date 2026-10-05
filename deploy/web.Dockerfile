# Atila's Client - portal (Flutter Web), built and served as static files
# behind nginx, which also reverse-proxies /api/ to the backend container.
# API_URL=/api makes the built app call its own origin - no CORS, no domain
# baked into the bundle, so the same image works behind any domain.
FROM ghcr.io/cirruslabs/flutter:3.38.5 AS build
WORKDIR /src

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY lib/ lib/
COPY assets/ assets/
COPY web/ web/
RUN flutter build web --release --dart-define=API_URL=/api

FROM nginx:alpine
COPY --from=build /src/build/web /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
