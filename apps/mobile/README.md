# proyecto-X — app (Expo)

App React Native (iOS/Android/Web) del shell de auth (F0.4).

## Desarrollo

### Instalación

```bash
npm install
# o pnpm install
```

### Configuración

La API se conecta a `http://localhost:8081` por defecto. Para cambiar:

```bash
export EXPO_PUBLIC_API_URL=http://tu-backend.local:8000
npx expo start
```

### Ejecutar

```bash
# iOS
npx expo start --ios

# Android
npx expo start --android

# Web
npx expo start --web
```

### Pruebas y Quality

```bash
# Tests
npm test

# Type checking
npx tsc --noEmit

# Lint
npx expo lint

# Export web
npx expo export -p web
```

## Estructura

- `src/app/` — Rutas con Expo Router
- `src/ui/` — Componentes base (Screen, Button, Text, etc.)
- `src/auth/` — Zustand store para sesión
- `src/api/` — Cliente HTTP y endpoints auth
- `__tests__/` — Test suite (Jest)

## Notas

- **Storage seguro:** `expo-secure-store` para tokens (refresh token)
- **State management:** Zustand para auth global
- **Gating:** Middleware en `src/app/_layout.tsx` que redirige según sesión
