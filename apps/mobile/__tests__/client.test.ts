jest.mock("../src/auth/storage", () => {
  let mem: any = null;
  return {
    getTokens: jest.fn(async () => mem),
    setTokens: jest.fn(async (t: any) => { mem = t; }),
    clearTokens: jest.fn(async () => { mem = null; }),
  };
});
import { useAuth } from "../src/auth/store";
import { apiFetch } from "../src/api/client";

function jsonRes(status: number, body: any): Response {
  return { ok: status < 400, status, json: async () => body } as unknown as Response;
}

test("on 401 it refreshes and retries once", async () => {
  await useAuth.getState().signIn({ access: "old", refresh: "r1" });
  const calls: string[] = [];
  (globalThis as any).fetch = jest.fn(async (url: any, init: any) => {
    calls.push(`${init?.method ?? "GET"} ${String(url)}`);
    if (String(url).endsWith("/me")) {
      // primera vez 401, segunda (con token nuevo) 200
      return calls.filter((c) => c.endsWith("/me")).length === 1
        ? jsonRes(401, {})
        : jsonRes(200, { ok: true });
    }
    if (String(url).endsWith("/auth/refresh")) return jsonRes(200, { access: "new", refresh: "r2" });
    return jsonRes(200, {});
  }) as any;

  const res = await apiFetch("/me", { auth: true });
  expect(res.status).toBe(200);
  expect(useAuth.getState().accessToken).toBe("new");
  expect(calls.some((c) => c.includes("/auth/refresh"))).toBe(true);
});
