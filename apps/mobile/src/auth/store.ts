import { create } from "zustand";
import { clearTokens, getTokens, setTokens, Tokens } from "./storage";

type Status = "loading" | "signedOut" | "signedIn";

type AuthState = {
  status: Status;
  accessToken: string | null;
  refreshToken: string | null;
  hydrate: () => Promise<void>;
  signIn: (t: Tokens) => Promise<void>;
  setAccess: (access: string, refresh: string) => Promise<void>;
  signOut: () => Promise<void>;
};

export const useAuth = create<AuthState>((set) => ({
  status: "loading",
  accessToken: null,
  refreshToken: null,
  hydrate: async () => {
    const t = await getTokens();
    set(t
      ? { status: "signedIn", accessToken: t.access, refreshToken: t.refresh }
      : { status: "signedOut", accessToken: null, refreshToken: null });
  },
  signIn: async (t) => {
    await setTokens(t);
    set({ status: "signedIn", accessToken: t.access, refreshToken: t.refresh });
  },
  setAccess: async (access, refresh) => {
    await setTokens({ access, refresh });
    set({ accessToken: access, refreshToken: refresh });
  },
  signOut: async () => {
    await clearTokens();
    set({ status: "signedOut", accessToken: null, refreshToken: null });
  },
}));
