import { apiFetch } from "./client";
import { LoginReq, RegisterReq, TokenPair } from "./types";

async function jsonOrThrow(res: Response): Promise<TokenPair> {
  if (!res.ok) throw new Error(`request_failed_${res.status}`);
  return (await res.json()) as TokenPair;
}

export const auth = {
  register: (body: RegisterReq) =>
    apiFetch("/auth/register", { method: "POST", body }).then(jsonOrThrow),
  login: (body: LoginReq) =>
    apiFetch("/auth/login", { method: "POST", body }).then(jsonOrThrow),
  verifyEmail: (code: string) =>
    apiFetch("/auth/verify-email", { method: "POST", body: { code }, auth: true }),
  resendEmail: () => apiFetch("/auth/resend-email", { method: "POST", auth: true }),
  logout: (refresh: string) =>
    apiFetch("/auth/logout", { method: "POST", body: { refresh } }),
};
