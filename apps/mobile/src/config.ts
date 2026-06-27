// Backend público (Cloudflare Tunnel → esta PC). Para dev local contra el API
// en localhost, exporta EXPO_PUBLIC_API_URL=http://localhost:8081 (o tu IP LAN
// si pruebas en un dispositivo físico apuntando a tu máquina).
export const API_URL =
  process.env.EXPO_PUBLIC_API_URL ?? "https://api.turnend.win";
