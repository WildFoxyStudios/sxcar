import { API_URL } from "../config";
import { useAuth } from "../auth/store";

type Options = { method?: string; body?: unknown; auth?: boolean };

async function raw(path: string, access: string | null, opts: Options): Promise<Response> {
  return fetch(`${API_URL}${path}`, {
    method: opts.method ?? "GET",
    headers: {
      "content-type": "application/json",
      ...(opts.auth && access ? { authorization: `Bearer ${access}` } : {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
}

/** Hace la petición; si 401 (con auth), intenta refresh una vez y reintenta. */
export async function apiFetch(path: string, opts: Options = {}): Promise<Response> {
  const { accessToken, refreshToken, setAccess, signOut } = useAuth.getState();
  let res = await raw(path, accessToken, opts);
  if (res.status === 401 && opts.auth && refreshToken) {
    const r = await raw("/auth/refresh", null, { method: "POST", body: { refresh: refreshToken } });
    if (r.ok) {
      const pair = (await r.json()) as { access: string; refresh: string };
      await setAccess(pair.access, pair.refresh);
      res = await raw(path, pair.access, opts);
    } else {
      await signOut();
    }
  }
  return res;
}
