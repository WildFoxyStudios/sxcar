jest.mock("../src/auth/storage", () => {
  let mem: any = null;
  return {
    getTokens: jest.fn(async () => mem),
    setTokens: jest.fn(async (t: any) => { mem = t; }),
    clearTokens: jest.fn(async () => { mem = null; }),
  };
});
import { useAuth } from "../src/auth/store";

test("session transitions signedOut → signedIn → signedOut", async () => {
  await useAuth.getState().hydrate();
  expect(useAuth.getState().status).toBe("signedOut");
  await useAuth.getState().signIn({ access: "a", refresh: "r" });
  expect(useAuth.getState().status).toBe("signedIn");
  expect(useAuth.getState().accessToken).toBe("a");
  await useAuth.getState().signOut();
  expect(useAuth.getState().status).toBe("signedOut");
});
